import { IAIProvider } from './AIProvider';
import { GroqProvider } from './GroqProvider';
import { OpenAIProvider } from './OpenAIProvider';

// ─────────────────────────────────────────────────────────────────────────────
// AIProviderFactory — reads ACTIVE_AI_PROVIDER from .env and returns the right
// provider. Adding a new provider only requires:
//   1. Create a new class implementing IAIProvider
//   2. Add a case below
// ─────────────────────────────────────────────────────────────────────────────

export function createAIProvider(): IAIProvider {
  const active = (process.env.ACTIVE_AI_PROVIDER ?? 'openai').toLowerCase();

  const preferred = active === 'groq' ? new GroqProvider() : new OpenAIProvider();
  if (preferred.isConfigured()) return preferred;

  // Keep OpenAI first by default, but use another configured real provider when
  // its credential is absent. This never substitutes mock or hardcoded output.
  const fallback = active === 'groq' ? new OpenAIProvider() : new GroqProvider();
  if (fallback.isConfigured()) {
    console.warn(`[AI] ${preferred.providerName} is not configured; using configured ${fallback.providerName} provider.`);
    return fallback;
  }

  switch (active) {
    case 'openai':
      return preferred;
    case 'groq':
      return preferred;
    default:
      console.warn(`[AI] Unknown ACTIVE_AI_PROVIDER=${active}; using OpenAI.`);
      return new OpenAIProvider();
  }
}

// Singleton
let _provider: IAIProvider | null = null;
export function getAIProvider(): IAIProvider {
  if (!_provider) {
    _provider = createAIProvider();
  }
  return _provider;
}
