# Política de execução pública de QA — Dialetto Builds

O repositório `dialetto-builds` é **público**. GitHub Actions logs e artefatos podem ser acessíveis a terceiros. Portanto, somente provas sem fonte privada e sem material sensível podem usar o perfil **public-safe**.

## Permitido sem credenciais
- Verificação de YAML, shell e scripts versionados **neste repositório público**.
- Probes de páginas **já públicas** de `https://dialetto.club`, sem login, sem tokens, sem cookies pessoais, sem dados de clientes.
- Testes de largura/viewport, overflow e controles visíveis com **resultado numérico/anônimo** em stdout.
- Fixtures sintéticas descartáveis; sem upload de imagens, HTML, HAR, trace, console de browser ou relatórios contendo dados da página.

## Não permitido em jobs public-safe
- Checkout do código-fonte privado `lucasouzadev/dialetto`, independentemente de permissão read-only.
- `secrets.*`, tokens Supabase de serviço, credenciais de conta de teste, chaves de assinatura, segredos de webhook ou credentials do backend.
- `actions/upload-artifact`, `gh release`, publicação de screenshots/vídeos, `adb logcat`/Maestro debug ou bundle/anexo de app privado.
- Workflow disparado automaticamente por PR privada usando token com acesso ao repositório privado.
- Migrações, testes RLS em dados reais, deployment, OTA, publicação de binários e benchmarks com fixtures privadas.

## Limites
`Public UX QA` monitora a versão do site **já publicada**, não um commit de PR ou build Capacitor. Ele **não** certifica layout iOS/Android nem substitui Maestro em staging. Resultados de CI só podem ser chamados PASS depois de a execução realmente concluir com sucesso.

Workflows legados de E2E/deploy/build neste repositório têm **outro perfil** e não são classificados como public-safe: alguns usam checkout privado, binários de debug, chaves, logs ou screenshots. Não deslocar novos testes de privacidade para esses pipelines antes de revisar a ameaça de exposição (incluindo dados existentes em branches/artefatos históricos) e obter armazenamento isolado/controle de acesso. A sanitização posterior de PNG/vídeo não é garantia suficiente.

**Sem exposição absoluta:** runners e fornecedores podem sofrer comprometimento; o objetivo operacional é não introduzir material sensível no job público. Se o teste exige material privado, ele não qualifica para este perfil e deve ser mantido em ambiente privado/protegido.
