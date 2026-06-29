export default {
  async fetch(request, env) {

    // CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'POST',
          'Access-Control-Allow-Headers': 'Content-Type, X-App-Key',
        }
      });
    }

    if (request.method !== 'POST') {
      return new Response('Method not allowed', { status: 405 });
    }

    // Chave secreta do app (define em Settings > Variables > Secrets)
    const appKey = request.headers.get('X-App-Key');
    if (appKey !== env.APP_SECRET) {
      return new Response('Unauthorized', { status: 401 });
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return new Response('Invalid JSON', { status: 400 });
    }

    const { remetente = '', assunto = '', snippet = '' } = body;

    const claudeRes = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'x-api-key': env.ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01',
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        model: 'claude-haiku-4-5-20251001',
        max_tokens: 300,
        system: `Você é um assistente de segurança de email. Analise o email e responda SOMENTE com JSON válido, sem texto extra:
{
  "seguro": true ou false,
  "nivel": "seguro" ou "suspeito" ou "perigoso",
  "resumo": "frase curta em português (máx 120 chars)",
  "alertas": ["lista de riscos encontrados"]
}
Seja objetivo. Não exagere alertas para emails normais.`,
        messages: [{
          role: 'user',
          content: `Remetente: ${remetente}\nAssunto: ${assunto}\nConteúdo: ${snippet.substring(0, 1000)}`
        }]
      })
    });

    const claudeData = await claudeRes.json();
    const raw = claudeData?.content?.[0]?.text ?? '{}';
    // Strip markdown code fences that Claude sometimes wraps around JSON
    const text = raw.replace(/^```(?:json)?\s*/i, '').replace(/\s*```\s*$/, '').trim();

    try {
      const parsed = JSON.parse(text);
      return new Response(JSON.stringify(parsed), {
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        }
      });
    } catch {
      return new Response(JSON.stringify({
        seguro: true,
        nivel: 'seguro',
        resumo: 'Análise indisponível no momento.',
        alertas: []
      }), {
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        }
      });
    }
  }
};
