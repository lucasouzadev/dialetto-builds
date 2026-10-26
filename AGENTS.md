# AGENTS.md — dialetto-builds (repositório PÚBLICO)

Aqui moram só workflows, fluxos E2E e scripts de CI do Dialetto. **Nenhum código do app** é guardado: cada execução clona o repositório privado `lucasouzadev/dialetto` com uma chave de leitura.
Logs e artefatos são públicos. As regras de trabalho estão no repositório privado: `CLAUDE.md`, `docs/agents/QUALITY_GATES_2026-10-14.md`, `docs/OTA_OU_BUILD.md`. Leia também `README.md` e `SECURE_PUBLIC_QA.md` daqui.

## Nunca, neste repositório
- Imprimir, registrar ou commitar segredo, token, chave, keystore, `.p8` ou algo decodificado deles. O GitHub mascara segredo só no log, nunca dentro de arquivo.
- Subir ou publicar screenshot, vídeo, HAR, trace, log do browser ou do `adb`, relatório com dado de página, SQL de erro ou conteúdo de usuário. Use fixtures sintéticas e passe tudo por `e2e/scrub_artifacts.py`.
- Adicionar `pull_request`, `pull_request_target`, `push` ou `schedule` a workflow que use segredo ou dispare build/deploy. Tudo é `workflow_dispatch`; a exceção é o `quality.yml`, que roda sozinho a cada 15 min **sem** artefatos e sem expor código (não aumente a frequência).
- Disparar `ios-testflight`, `android-apk` ou `ios-check` sem **ordem explícita do autor** (cada build manda e-mail da Apple a testadores). OTA é merge em `main` e não passa por aqui.
- Rodar teste que toque código ou schema privado, RLS em dado real, migration ou benchmark em job `public-safe` (`SECURE_PUBLIC_QA.md`). Marque `BLOCKED`, não `PASS`.
- Mexer em workflow "para ver o que acontece": quem edita um workflow lê os segredos que ele usa. Mudança de workflow vai por PR, com o diff lido.

## Como trabalhar
- Um merge no privado **não** faz deploy de Supabase nem do worker: rode "Supabase deploy" / "Worker deploy" aqui, antes com `dry_run`. Trate log de falha como público.
- Rode o `Check` antes de propor mudança em workflow ou fluxo. No máximo uma execução de cada plataforma em voo; leia o resumo e o screenshot que falhou antes de rodar de novo.
- Teste não executado é `BLOCKED`. Distinga sempre: merge, deploy executado e produção confirmada.
