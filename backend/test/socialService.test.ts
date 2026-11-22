import test from 'node:test';
import assert from 'node:assert/strict';
import { SocialDb } from '../src/db/socialDb';
import {
  SocialService,
  UsernameTakenError,
  InvalidUsernameError,
  ForbiddenError,
  NotFoundError,
} from '../src/services/SocialService';

function freshService() {
  return new SocialService(new SocialDb(':memory:'));
}

test('creates a real profile with a generated unique username on first login', () => {
  const svc = freshService();
  const { userId, isNewUser } = svc.findOrCreateUserByEmail('nour@example.com');
  assert.equal(isNewUser, true);
  const profile = svc.getProfileByUserId(userId);
  assert.ok(profile);
  assert.ok(profile!.username.length >= 3);
  assert.equal(profile!.followersCount, 0);
});

test('logging in again with the same email returns the same account, not a new one', () => {
  const svc = freshService();
  const first = svc.findOrCreateUserByEmail('same@example.com');
  const second = svc.findOrCreateUserByEmail('SAME@example.com'); // case-insensitive
  assert.equal(first.userId, second.userId);
  assert.equal(second.isNewUser, false);
});

test('username validation rejects invalid formats and enforces uniqueness', () => {
  const svc = freshService();
  const a = svc.findOrCreateUserByEmail('a@example.com').userId;
  const b = svc.findOrCreateUserByEmail('b@example.com').userId;
  assert.throws(() => svc.updateProfile(a, { username: '!!' }), InvalidUsernameError);
  svc.updateProfile(a, { username: 'realname' });
  assert.throws(() => svc.updateProfile(b, { username: 'realname' }), UsernameTakenError);
  // Case-insensitive collision too.
  assert.throws(() => svc.updateProfile(b, { username: 'RealName' }), UsernameTakenError);
});

test('follow/unfollow updates both sides\' counters correctly and is idempotent', () => {
  const svc = freshService();
  const a = svc.findOrCreateUserByEmail('a@example.com').userId;
  const b = svc.findOrCreateUserByEmail('b@example.com').userId;
  svc.follow(a, b);
  svc.follow(a, b); // idempotent — no double count
  assert.equal(svc.getProfileByUserId(a)!.followingCount, 1);
  assert.equal(svc.getProfileByUserId(b)!.followersCount, 1);
  svc.unfollow(a, b);
  assert.equal(svc.getProfileByUserId(a)!.followingCount, 0);
  assert.equal(svc.getProfileByUserId(b)!.followersCount, 0);
});

test('cannot follow yourself', () => {
  const svc = freshService();
  const a = svc.findOrCreateUserByEmail('a@example.com').userId;
  assert.throws(() => svc.follow(a, a), ForbiddenError);
});

test('a post stores only the YouTube reference, never a media duplicate', () => {
  const svc = freshService();
  const author = svc.findOrCreateUserByEmail('author@example.com').userId;
  const post = svc.createPost(author, {
    youtubeVideoId: 'dQw4w9WgXcQ',
    trackTitle: 'Never Gonna Give You Up',
    artist: 'Rick Astley',
    caption: 'classic',
  });
  assert.equal(post.youtubeVideoId, 'dQw4w9WgXcQ');
  assert.equal(svc.getProfileByUserId(author)!.postsCount, 1);
});

test('like/unlike prevents duplicate likes and keeps counts correct', () => {
  const svc = freshService();
  const author = svc.findOrCreateUserByEmail('author@example.com').userId;
  const liker = svc.findOrCreateUserByEmail('liker@example.com').userId;
  const post = svc.createPost(author, { youtubeVideoId: 'dQw4w9WgXcQ', trackTitle: 'T', artist: 'A' });
  svc.likePost(post.id, liker);
  svc.likePost(post.id, liker); // duplicate, ignored
  assert.equal(svc.getPost(post.id)!.likesCount, 1);
  svc.unlikePost(post.id, liker);
  assert.equal(svc.getPost(post.id)!.likesCount, 0);
});

test('a repost points at the original post and does not duplicate it', () => {
  const svc = freshService();
  const author = svc.findOrCreateUserByEmail('author@example.com').userId;
  const reposter = svc.findOrCreateUserByEmail('reposter@example.com').userId;
  const post = svc.createPost(author, { youtubeVideoId: 'dQw4w9WgXcQ', trackTitle: 'T', artist: 'A' });
  svc.repost(reposter, post.id, 'love this');
  assert.equal(svc.getPost(post.id)!.repostsCount, 1);
  // A second repost by the same user does not double-count.
  svc.repost(reposter, post.id, null);
  assert.equal(svc.getPost(post.id)!.repostsCount, 1);
});

test('comments support a nullable parent for future threading, and delete is author-only', () => {
  const svc = freshService();
  const author = svc.findOrCreateUserByEmail('author@example.com').userId;
  const commenter = svc.findOrCreateUserByEmail('commenter@example.com').userId;
  const post = svc.createPost(author, { youtubeVideoId: 'dQw4w9WgXcQ', trackTitle: 'T', artist: 'A' });
  const comment = svc.addComment(post.id, commenter, 'nice', null);
  assert.equal(comment.parentCommentId, null);
  assert.equal(svc.getPost(post.id)!.commentsCount, 1);
  assert.throws(() => svc.deleteComment(comment.id, author), ForbiddenError);
  svc.deleteComment(comment.id, commenter);
  assert.equal(svc.getPost(post.id)!.commentsCount, 0);
});

test('every post embeds a lightweight author summary — no N+1 query needed to render a feed card', () => {
  const svc = freshService();
  const author = svc.findOrCreateUserByEmail('author@example.com').userId;
  svc.updateProfile(author, { username: 'thefeeduser', displayName: 'The Feed User' });
  svc.createPost(author, { youtubeVideoId: 'dQw4w9WgXcQ', trackTitle: 'T', artist: 'A' });

  for (const post of svc.getFeed(null, null, 10).items) {
    assert.ok(post.author, 'feed post missing author');
    assert.equal(post.author!.username, 'thefeeduser');
    assert.equal(post.author!.displayName, 'The Feed User');
  }
  const single = svc.getPost(svc.getFeed(null, null, 1).items[0].id);
  assert.equal(single!.author!.username, 'thefeeduser');
});

test('feed is cursor-paginated and never returns more than the requested page size', () => {
  const svc = freshService();
  const author = svc.findOrCreateUserByEmail('author@example.com').userId;
  for (let i = 0; i < 25; i++) {
    svc.createPost(author, { youtubeVideoId: 'dQw4w9WgXcQ', trackTitle: `T${i}`, artist: 'A' });
  }
  const page1 = svc.getFeed(null, null, 10);
  assert.equal(page1.items.length, 10);
  assert.ok(page1.nextCursor);
  const page2 = svc.getFeed(null, page1.nextCursor, 10);
  assert.equal(page2.items.length, 10);
  // No overlap between pages.
  const ids1 = new Set(page1.items.map((p) => p.id));
  for (const p of page2.items) assert.ok(!ids1.has(p.id));
});

test('a personalized feed prioritizes followed authors over the public feed', () => {
  const svc = freshService();
  const viewer = svc.findOrCreateUserByEmail('viewer@example.com').userId;
  const followed = svc.findOrCreateUserByEmail('followed@example.com').userId;
  const stranger = svc.findOrCreateUserByEmail('stranger@example.com').userId;
  svc.follow(viewer, followed);
  svc.createPost(stranger, { youtubeVideoId: 'dQw4w9WgXcQ', trackTitle: 'Stranger track', artist: 'A' });
  const followedPost = svc.createPost(followed, { youtubeVideoId: 'dQw4w9WgXcQ', trackTitle: 'Followed track', artist: 'A' });
  const feed = svc.getFeed(viewer, null, 10);
  assert.equal(feed.items.length, 1);
  assert.equal(feed.items[0].id, followedPost.id);
});

test('blocking severs an existing follow relationship in both directions', () => {
  const svc = freshService();
  const a = svc.findOrCreateUserByEmail('a@example.com').userId;
  const b = svc.findOrCreateUserByEmail('b@example.com').userId;
  svc.follow(a, b);
  svc.follow(b, a);
  svc.blockUser(a, b);
  assert.equal(svc.isFollowing(a, b), false);
  assert.equal(svc.isFollowing(b, a), false);
  assert.equal(svc.isBlocked(a, b), true);
});

test('a blocked feed author is excluded from the viewer\'s public feed', () => {
  const svc = freshService();
  const viewer = svc.findOrCreateUserByEmail('viewer@example.com').userId;
  const blocked = svc.findOrCreateUserByEmail('blocked@example.com').userId;
  svc.createPost(blocked, { youtubeVideoId: 'dQw4w9WgXcQ', trackTitle: 'T', artist: 'A' });
  svc.blockUser(viewer, blocked);
  const feed = svc.getFeed(viewer, null, 10);
  assert.equal(feed.items.length, 0);
});

test('reports are recorded with a valid target type', () => {
  const svc = freshService();
  const reporter = svc.findOrCreateUserByEmail('reporter@example.com').userId;
  const result = svc.report(reporter, 'post', 'post_123', 'spam', 'looks fake');
  assert.ok(result.id);
});

test('notifications are created for follow/like/comment/repost but never for your own action', () => {
  const svc = freshService();
  const a = svc.findOrCreateUserByEmail('a@example.com').userId;
  const post = svc.createPost(a, { youtubeVideoId: 'dQw4w9WgXcQ', trackTitle: 'T', artist: 'A' });
  svc.likePost(post.id, a); // liking your own post
  assert.equal(svc.unreadNotificationCount(a), 0);

  const b = svc.findOrCreateUserByEmail('b@example.com').userId;
  svc.likePost(post.id, b);
  assert.equal(svc.unreadNotificationCount(a), 1);
  const page = svc.listNotifications(a, null, 10);
  assert.equal(page.items[0].type, 'like');
  svc.markNotificationsRead(a, 'all');
  assert.equal(svc.unreadNotificationCount(a), 0);
});

test('deleteAccount really erases data, not just hides it, and fixes up others\' counters', () => {
  const svc = freshService();
  const alice = svc.findOrCreateUserByEmail('alice@example.com').userId;
  const bob = svc.findOrCreateUserByEmail('bob@example.com').userId;
  svc.follow(alice, bob);
  const bobPost = svc.createPost(bob, { youtubeVideoId: 'dQw4w9WgXcQ', trackTitle: 'T', artist: 'A' });
  svc.likePost(bobPost.id, alice);
  svc.addComment(bobPost.id, alice, 'nice', null);

  svc.deleteAccount(alice);

  assert.equal(svc.getProfileByUserId(alice), null);
  const refreshedBobPost = svc.getPost(bobPost.id)!;
  assert.equal(refreshedBobPost.likesCount, 0, 'like from the deleted user must be unwound');
  assert.equal(refreshedBobPost.commentsCount, 0, 'comment from the deleted user must be unwound');
  assert.equal(svc.getProfileByUserId(bob)!.followersCount, 0, "bob's follower count must reflect alice's removal");
});

test('save/unsave a post is private to the saving user and cursor-paginated', () => {
  const svc = freshService();
  const author = svc.findOrCreateUserByEmail('author@example.com').userId;
  const saver = svc.findOrCreateUserByEmail('saver@example.com').userId;
  const post = svc.createPost(author, { youtubeVideoId: 'dQw4w9WgXcQ', trackTitle: 'T', artist: 'A' });

  svc.savePost(saver, post.id);
  svc.savePost(saver, post.id); // idempotent, no duplicate row (PK on (user_id, post_id))
  let saved = svc.listSaved(saver, null, 10);
  assert.equal(saved.items.length, 1);
  assert.equal(saved.items[0].id, post.id);

  // Not visible to a different user's saved list.
  assert.equal(svc.listSaved(author, null, 10).items.length, 0);

  svc.unsavePost(saver, post.id);
  saved = svc.listSaved(saver, null, 10);
  assert.equal(saved.items.length, 0);
});

test('private session preferences are stored per user and default to off', () => {
  const svc = freshService();
  const a = svc.findOrCreateUserByEmail('a@example.com').userId;
  assert.deepEqual(svc.getPreferences(a), { privateSession: false, aiPersonalizationEnabled: true });
  svc.setPreferences(a, { privateSession: true });
  assert.equal(svc.getPreferences(a).privateSession, true);
  assert.equal(svc.getPreferences(a).aiPersonalizationEnabled, true);
});

// ─── Username + password accounts ──────────────────────────────────────────

test('registers a real username/password account with no email at all', () => {
  const svc = freshService();
  const { userId, isNewUser } = svc.registerWithUsernamePassword('kero_music', 'hashed:value');
  assert.equal(isNewUser, true);
  const profile = svc.getProfileByUserId(userId);
  assert.equal(profile!.username, 'kero_music');
  // No email on file for a pure username/password account.
  const found = svc.getPasswordHashByUsername('kero_music');
  assert.equal(found!.userId, userId);
  assert.equal(found!.passwordHash, 'hashed:value');
});

test('username/password registration rejects invalid usernames and duplicates', () => {
  const svc = freshService();
  assert.throws(() => svc.registerWithUsernamePassword('!!', 'h'), InvalidUsernameError);
  svc.registerWithUsernamePassword('taken_name', 'h1');
  assert.throws(() => svc.registerWithUsernamePassword('taken_name', 'h2'), UsernameTakenError);
  assert.throws(() => svc.registerWithUsernamePassword('TAKEN_NAME', 'h3'), UsernameTakenError, 'case-insensitive');
});

test('getPasswordHashByUsername returns null for a username that does not exist', () => {
  const svc = freshService();
  assert.equal(svc.getPasswordHashByUsername('nobody_here'), null);
});

test('getPasswordHashByUsername returns null for an account that has no password set (e.g. email/Apple sign-in)', () => {
  const svc = freshService();
  const { userId } = svc.findOrCreateUserByEmail('emailonly@example.com');
  const profile = svc.getProfileByUserId(userId)!;
  // This account was never given a password — must not be usable for
  // username/password login even though it has a real username.
  assert.equal(svc.getPasswordHashByUsername(profile.username), null);
});

// ─── Google accounts ────────────────────────────────────────────────────────

test('creates a real profile on first Google sign-in, and reuses the same account on the next one', () => {
  const svc = freshService();
  const first = svc.findOrCreateUserByGoogleSub('google-sub-1', 'listener@gmail.com');
  assert.equal(first.isNewUser, true);
  const second = svc.findOrCreateUserByGoogleSub('google-sub-1', 'listener@gmail.com');
  assert.equal(second.isNewUser, false);
  assert.equal(second.userId, first.userId);
});

test('two different Google accounts never collide', () => {
  const svc = freshService();
  const a = svc.findOrCreateUserByGoogleSub('google-sub-a', 'a@gmail.com');
  const b = svc.findOrCreateUserByGoogleSub('google-sub-b', 'b@gmail.com');
  assert.notEqual(a.userId, b.userId);
});
