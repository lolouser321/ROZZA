// ─────────────────────────────────────────────────────────────────────────────
// EmailSender — abstraction so the email sign-in code path never fabricates
// delivery. Real delivery is via Resend when RESEND_API_KEY is set (see
// ResendEmailSender below); otherwise the only implementation logs the code
// to the server console rather than pretending to send it. Swapping in a
// different provider (Postmark/SES/SMTP) later is exactly one new class
// implementing this interface plus an env var — no caller changes.
// ─────────────────────────────────────────────────────────────────────────────

export interface EmailSender {
  readonly isConfigured: boolean;
  send(to: string, subject: string, body: string): Promise<boolean>;
}

/** Development-only stand-in — genuinely does NOT send anywhere. Used
 *  whenever no real provider key is configured, so the code is at least
 *  readable by whoever has server access instead of vanishing. Never
 *  presented to end users as "email sent"; see routes/auth.ts, which
 *  reports delivered:false whenever this is the active sender. */
class ConsoleEmailSender implements EmailSender {
  readonly isConfigured = true;

  async send(to: string, subject: string, body: string): Promise<boolean> {
    console.log(`[EmailSender:console] To: ${to} | Subject: ${subject}\n${body}`);
    return true;
  }
}

/** Real delivery via Resend (https://resend.com) — a plain REST call, no
 *  SDK dependency needed. `RESEND_FROM` must be an address Resend will
 *  actually let this account send from: either `onboarding@resend.dev`
 *  (works immediately, no domain setup, but Resend only delivers it to
 *  the email the account itself was created with — fine for solo/testing
 *  use, not for arbitrary users) or an address on a domain verified in
 *  the Resend dashboard (works for any recipient). Never claims success
 *  on a non-2xx response — `send()` returns exactly what really
 *  happened. */
export class ResendEmailSender implements EmailSender {
  readonly isConfigured = true;
  constructor(
    private readonly apiKey: string,
    private readonly from: string,
    // Injectable for tests — real requests use the global fetch.
    private readonly fetchImpl: typeof fetch = fetch
  ) {}

  async send(to: string, subject: string, body: string): Promise<boolean> {
    try {
      const response = await this.fetchImpl('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${this.apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ from: this.from, to, subject, text: body }),
        signal: AbortSignal.timeout(10_000),
      });
      if (!response.ok) {
        const detail = await response.text().catch(() => '');
        console.error(`[EmailSender:resend] send failed: HTTP ${response.status} ${detail}`);
        return false;
      }
      return true;
    } catch (err: any) {
      console.error('[EmailSender:resend] send threw:', err?.message ?? err);
      return false;
    }
  }
}

let _sender: EmailSender | null = null;
export function getEmailSender(): EmailSender {
  if (!_sender) {
    const resendKey = process.env.RESEND_API_KEY;
    if (resendKey) {
      _sender = new ResendEmailSender(resendKey, process.env.RESEND_FROM || 'onboarding@resend.dev');
    } else {
      _sender = new ConsoleEmailSender();
    }
  }
  return _sender;
}
