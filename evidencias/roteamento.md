# Roteamento de modelos no gateway — evidência

Coleta: 2026-11-10T00:46Z
Gateway: `https://api.kodeo.com.br`
Plano: Kodeo Max (`plan: max`)

## Resumo

Modelos que o plano anuncia (9). Quatro não são servidos por eles mesmos: o
gateway substitui por `minimax-m2.7` e devolve HTTP 200, sem erro.

| Pedido | `corpo.model` | `x-kodeo-provedor` | `x-kodeo-substituto` | Quem respondeu de fato |
|---|---|---|---|---|
| `minimax-m2.7` | minimax-m2.7 | g7 | — | MiniMax-M2.7 ✓ |
| `glm-5.3-flash` | glm-5.3-flash | g7 | — | GLM ✓ |
| `deepseek-v4-flash` | deepseek-v4-flash | g7 | — | "DeepSeek-V3" (versão diferente) ⚠ |
| `grok-4.7` | **minimax-m2.7** | g7 | `grok-4.7>minimax-m2.7` | MiniMax-M2.7 ✗ |
| `claude-opus-5` | claude-opus-5 | p5:claude-opus-5 | — | Claude Opus 5 ✓ |
| `claude-haiku-5.5` | **minimax-m2.7** | g7 | `claude-haiku-5.5>minimax-m2.7` | MiniMax-M2.7 ✗ |
| `claude-opus-5.5` | claude-opus-5.5 | p5:claude-opus-5-5 | — | Claude ✓ |
| `gpt-6-sol` | **minimax-m2.7** | g7 | `gpt-6-sol>minimax-m2.7` | MiniMax-M2.7 ✗ |
| `gpt-6-astra` | **minimax-m2.7** | g7 | `gpt-6-astra>minimax-m2.7` | MiniMax-M2.7 ✗ |

## Prova 1 — o mesmo `id` aparece em cinco modelos

Rodando `evidencias/verificar.sh`, o agrupamento por `id` da resposta mostra:

```
id=devshard-162720-1881  tokens=376
   claude-haiku-5.5     sha1(texto)=1e0d1bd6443ae087
   gpt-6-astra          sha1(texto)=1e0d1bd6443ae087
   gpt-6-sol            sha1(texto)=1e0d1bd6443ae087
   grok-4.7             sha1(texto)=1e0d1bd6443ae087
   minimax-m2.7         sha1(texto)=1e0d1bd6443ae087

id=devshard-162758-665  tokens=310
   deepseek-v4-flash    sha1(texto)=beffcfb5d5bd65b2

id=devshard-162779-634  tokens=205
   glm-5.3-flash        sha1(texto)=92f87f37b94a9e8f

id=req_02d9b7f1319771c1  tokens=243
   claude-opus-5.5      sha1(texto)=3de9e752907c9df4
```

O `minimax-m2.7` legítimo compartilha `id` e SHA1 com os quatro substituídos —
é a confirmação de que são a mesma resposta. Os demais têm `id` próprio e texto
próprio.

## Prova 1b — os quatro substituídos devolvem o MESMO objeto

Requisições distintas, modelos distintos, respostas indistinguíveis:

| Pedido | `id` da resposta | SHA1 do texto | tokens |
|---|---|---|---|
| `grok-4.7` | `devshard-162720-1881` | `1e0d1bd6443ae087` | 376 |
| `claude-haiku-5.5` | `devshard-162720-1881` | `1e0d1bd6443ae087` | 376 |
| `gpt-6-sol` | `devshard-162720-1881` | `1e0d1bd6443ae087` | 376 |
| `gpt-6-astra` | `devshard-162720-1881` | `1e0d1bd6443ae087` | 376 |

Quatro modelos diferentes produzindo o mesmo `id`, o mesmo texto (byte a byte)
e a mesma contagem de tokens: é o mesmo backend respondendo às quatro.

## Prova 2 — o header declara a substituição

Resposta para `gpt-6-sol` em `POST /v1/chat/completions`:

```
HTTP/2 200
x-kodeo-provedor: g7
x-kodeo-roteamento: ligado
x-kodeo-substituto: gpt-6-sol>minimax-m2.7
```

Compare com `claude-opus-5.5`, que não é substituído:

```
HTTP/2 200
x-kodeo-provedor: p5:claude-opus-5-5
x-kodeo-roteamento: ligado
                                  ← sem x-kodeo-substituto
```

O próprio gateway informa qual backend serviu. `g7` é o backend do MiniMax;
`p5:*` são os backends diretos.

## Prova 3 — em /v1/responses o campo `model` esconde a substituição

O Codex usa `/v1/responses`. Ali o campo `model` da resposta **ecoa o pedido**,
mas o texto entregue é o do MiniMax:

| Pedido | `corpo.model` diz | texto real | SHA1 |
|---|---|---|---|
| `gpt-6-sol` | `gpt-6-sol` | "MiniMax-M2.7" | `1e0d1bd6443ae087` |
| `gpt-6-astra` | `gpt-6-astra` | "MiniMax-M2.7" | `1e0d1bd6443ae087` |

O SHA1 é o mesmo dos quatro substituídos no outro endpoint. Só o header
`x-kodeo-substituto` revela a troca. Um cliente que leia apenas o corpo conclui
que recebeu `gpt-6-sol`.

## Prova 4 — a cobrança é a do modelo pedido

`gpt-6-sol` e `minimax-m2.7` devolvem a mesma contagem de tokens (376 na mesma
pergunta). Não há desconto por receber modelo diferente do contratado.

## Prova 5 — o catálogo anuncia o que não entrega

`GET /v1/me` → `modelos` lista os 9, incluindo os 4 que são substituídos:

```
minimax-m2.7, glm-5.3-flash, deepseek-v4-flash, grok-4.7,
claude-opus-5, claude-haiku-5.5, claude-opus-5.5, gpt-6-sol, gpt-6-astra
```

`GET /v1/models` lista 22, incluindo modelos de planos superiores.

## Reprodução

```sh
K="<sua chave>"

# o header entrega
curl -sD - -o /dev/null https://api.kodeo.com.br/v1/chat/completions \
  -H "Authorization: Bearer $K" -H 'content-type: application/json' \
  -d '{"model":"gpt-6-sol","messages":[{"role":"user","content":"oi"}],"max_tokens":5}' \
  | grep -i 'x-kodeo'

# e o corpo confirma
curl -s https://api.kodeo.com.br/v1/chat/completions \
  -H "Authorization: Bearer $K" -H 'content-type: application/json' \
  -d '{"model":"gpt-6-sol","messages":[{"role":"user","content":"Qual e o seu modelo? Responda apenas o nome."}],"max_tokens":40}' \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["model"], "|", d["choices"][0]["message"]["content"])'
```

## Observações

- **Nenhum header do cliente desliga** o roteamento. Testados: `x-kodeo-roteamento`,
  `x-kodeo-substituto`, `x-kodeo-router`, `x-kodeo-fallback`, `X-Kodeo-No-Routing`.
  Todos mantiveram a substituição.
- Não existe endpoint de configuração: `/v1/config`, `/v1/settings`,
  `/v1/roteamento`, `/v1/routing` → 404.
- `deepseek-v4-flash` responde "DeepSeek-V3": o nome promete v4, o modelo diz ser
  v3. Não é substituição (o header não aparece), mas é outra divergência entre o
  nome anunciado e o modelo servido.

## Perguntas objetivas para o provedor

1. Por que `gpt-6-sol`, `gpt-6-astra`, `grok-4.7` e `claude-haiku-5.5` são
   servidos por `minimax-m2.7` sob HTTP 200, sem erro nem aviso ao cliente?
2. O header `x-kodeo-substituto` indica que a substituição é intencional e
   declarada. Qual é o critério, e por que o campo `model` de `/v1/responses`
   informa o modelo pedido em vez do servido?
3. A cobrança de uma requisição substituída é a do modelo pedido ou a do
   substituto? A contagem de tokens é idêntica nos dois casos observados.
4. `deepseek-v4-flash` responde como "DeepSeek-V3". Qual modelo é servido?
5. Existe como o cliente optar por receber erro em vez de substituto?
