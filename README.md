# dialetto-builds

Ambiente dedicado para criar, testar e publicar builds do Dialetto (BETA).

O código do app fica no repositório **privado** `lucasouzadev/dialetto`. Este repositório é **público** de propósito: o GitHub não cobra minutos de Actions em repositórios públicos, e foi a cota do repositório privado que acabou. Aqui moram só os workflows, os fluxos de teste E2E e alguns scripts. **Nenhum código do app é guardado aqui**: cada execução clona o privado com uma chave de leitura (`DIALETTO_DEPLOY_KEY`), constrói e descarta.

```
 você / Claude                       lucasouzadev/dialetto (privado)
      │  Run workflow                        ▲  clone somente-leitura
      ▼                                      │  (deploy key)
 dialetto-builds (público) ──────────────────┘
      ├─ Build ............ APK (Release opcional) · simulador iOS · TestFlight
      ├─ E2E Android ...... emulador + Maestro
      ├─ E2E iOS .......... simulador + Maestro
      ├─ Supabase deploy .. migrations + Edge Functions
      ├─ Worker deploy .... Fly.io
      └─ OTA .............. confere (e dispara) a atualização over-the-air
```

**Nada aqui roda sozinho.** Tudo é `workflow_dispatch` (Actions → escolher o workflow → *Run workflow*). Um merge no repositório privado **não** faz deploy: você (ou o agente) roda o workflow.

## Workflows

| Workflow | Para quê | Entradas principais |
|---|---|---|
| **Build** | APK de debug, app de simulador iOS, TestFlight | `target`, `ref`, `publish_release` |
| **E2E (Android emulator)** | Constrói o APK, abre um emulador e roda os fluxos Maestro | `ref`, `tags` |
| **E2E (iOS simulator)** | Constrói para o simulador, abre um iPhone e roda os fluxos | `ref`, `tags` |
| **Supabase deploy** | Aplica migrations e faz deploy das Edge Functions | `ref`, `dry_run`, `deploy_migrations`, `deploy_functions`, … |
| **Worker deploy** | Testa e faz deploy do worker no Fly.io, com health check | `ref`, `skip_tests`, `skip_health` |
| **OTA** | Confere o que os apps instalados receberiam; `redeploy` pede o deploy ao Vercel | `action`, `ref` |
| **Check** | Valida os próprios workflows e fluxos (automático, sem secrets) | — |

`ref` é a branch, tag ou commit de `lucasouzadev/dialetto` (padrão `main`).

### Build
- `android-apk`: gera o APK de debug. Baixe em **Artifacts** da execução ou marque `publish_release` para publicá-lo numa **pré-release** do GitHub (`android-b<número>`), com o checksum na descrição.
- `ios-check` / `android-and-ios-check`: só compila (sem assinatura). Prova que o shell constrói, não gera app instalável.
- `ios-testflight`: arquiva, assina e envia ao App Store Connect. **Envia e-mails da Apple a você e aos testadores**: rode de propósito. Usa o Environment `ios-release` (veja a segurança abaixo).

### E2E
Os fluxos ficam em `e2e/flows` (YAML do [Maestro](https://maestro.mobile.dev), versão fixada e verificada por checksum). Cada execução sobe como artefato o relatório, os screenshots, o log (Android) ou a gravação de tela (iOS), e o resumo do job lista cada fluxo. Isso permite diagnosticar uma falha sem ninguém com o celular na mão.

- **Sem conta de teste** (`E2E_EMAIL` / `E2E_PASSWORD` ausentes) só rodam os fluxos sem login (`01-smoke`).
- **Com conta de teste** rodam também os fluxos com a tag `login`.
- Os fluxos **não alteram dados**: só navegam e conferem telas. A conta de teste é uma conta real em produção (não existe ambiente de staging), então crie uma conta **dedicada e vazia**, nunca a sua.
- O simulador de iOS não recebe push de verdade; push se confere no Android e em aparelho real.
- Os fluxos foram validados só quanto à sintaxe (`maestro check-syntax`). **A primeira execução real provavelmente exigirá ajustar seletores** (textos de tela, tempos de espera). É esperado: rode com `tags: smoke`, leia o resumo e os screenshots, e corrija.

### OTA
O pacote OTA **não é construído aqui**. Cada deploy do site no Vercel publica `/ota/latest.json` e o zip, e os apps só os aceitam de `dialetto.club`. Então "subir uma OTA" é "ter a `main` implantada no Vercel", o que o Vercel faz sozinho a cada merge (não depende de Actions).
- `verify`: lê o que está no ar e confere versão, checksum do zip e `minNativeBuild` contra o commit informado.
- `redeploy`: chama o Deploy Hook do Vercel e espera o novo OTA ficar no ar. Só funciona para `main`.

## Configuração (uma vez)

### 1. Acesso de leitura ao repositório privado
O secret `DIALETTO_DEPLOY_KEY` aceita **uma de duas** credenciais. Em qualquer caso o workflow só **lê** o `dialetto`.

**Opção A, recomendada: chave SSH de deploy** (só dá acesso a este repositório, e a leitura é imposta pelo GitHub).
```bash
ssh-keygen -t ed25519 -N "" -C "dialetto-builds" -f dialetto-builds-key
```
- `dialetto-builds-key.pub` → repositório **`dialetto`** → *Settings → Deploy keys → Add deploy key*, **sem** marcar "Allow write access".
- `dialetto-builds-key` (a privada, o arquivo inteiro, da linha `BEGIN` à linha `END`) → secret `DIALETTO_DEPLOY_KEY` **deste** repositório. Também vale o **base64** do arquivo. Depois apague os dois arquivos locais.

**Opção B: token do GitHub.** Crie um *fine-grained personal access token* (Settings → Developer settings → Fine-grained tokens) com **só** o repositório `lucasouzadev/dialetto` e a permissão **Contents: Read-only**, e cole-o no mesmo secret. Antes de clonar, o script consulta a API do GitHub para confirmar visibilidade do repositório e acesso de leitura ao código. Essa consulta **não confirma o escopo de escrita do token**: o campo `permissions` do repositório reflete o papel da conta, por isso o dono pode aparecer como administrador mesmo usando um token de leitura. Configure o escopo mínimo na criação do token; se precisar que a leitura seja imposta por uma credencial exclusiva do repositório, use a chave SSH da opção A. Tokens *classic* (`ghp_...`) e outros tipos não são aceitos. Um token que você não usa mais deve ser revogado.

### 2. Secrets (Settings → Secrets and variables → Actions)

| Secret | Usado por | De onde vem |
|---|---|---|
| `DIALETTO_DEPLOY_KEY` | todos | passo 1 |
| `ANDROID_KEYSTORE_BASE64` | Build, E2E Android | seu `.jks` em base64 (`base64 -w0 dialetto.jks`) |
| `ANDROID_KEYSTORE_PASSWORD` | idem | você |
| `ANDROID_KEY_ALIAS` | idem | você |
| `ANDROID_KEY_PASSWORD` | idem | você |
| `APP_STORE_CONNECT_KEY_ID` | Build (TestFlight) | App Store Connect → Integrations |
| `APP_STORE_CONNECT_ISSUER_ID` | idem | idem (UUID) |
| `APP_STORE_CONNECT_API_KEY` | idem | texto completo do `.p8` |
| `APPLE_TEAM_ID` | idem | Apple Developer |
| `SUPABASE_ACCESS_TOKEN` | Supabase deploy | https://supabase.com/dashboard/account/tokens |
| `SUPABASE_DB_PASSWORD` | idem | senha do banco do projeto |
| `SUPABASE_PROJECT_ID` | idem | `ohcgrtaultutxmcpoicl` |
| `FLY_API_TOKEN` | Worker deploy | token de deploy do app `dialetto-worker` |
| `VERCEL_DEPLOY_HOOK_URL` | OTA `redeploy` (opcional) | Vercel → Project → Settings → Git → Deploy Hooks |
| `E2E_EMAIL`, `E2E_PASSWORD` | E2E (opcional) | conta de teste dedicada |

O GitHub **nunca mostra um secret depois de salvo**: guarde os originais num gerenciador de senhas. Sem o `.jks` o APK sai com uma chave de debug que muda a cada execução (o app instalado não atualiza por cima e os App Links deixam de validar). Sem a chave de Android o build ainda funciona, com um aviso.

**Não** coloque aqui nenhuma chave de serviço do Supabase, do Stripe, do Resend ou do worker: nada neste repositório precisa delas. As `VITE_*` dos workflows são valores públicos (os mesmos que o site já entrega).

### 3. Variável (Settings → Secrets and variables → Actions → Variables)
- `BUILD_NUMBER_OFFSET` (padrão `100`). O número do build é `offset + número da execução`. Este repositório é novo, então o contador do GitHub recomeçou em 1, mas o TestFlight e os Androids instalados já viram números acima de 50 e **não aceitam um menor**. Se o último build antigo passou de 100, aumente o offset **antes** do primeiro build.

### 4. Ajustes de segurança do repositório (Settings)
O repositório é público, então estes ajustes importam:
- **Actions → General → Fork pull request workflows**: exigir aprovação para todos os colaboradores externos. Secrets nunca são entregues a forks (padrão do GitHub); mantenha assim.
- **Actions → General → Workflow permissions**: *Read repository contents* (cada workflow pede só o que precisa).
- **Environments**: crie `production` e `ios-release`. Em cada um, marque você como *Required reviewer*. Assim todo deploy de Supabase/worker e todo envio ao TestFlight **espera sua aprovação**. Se preferir, mova os secrets do Supabase, Fly e Apple para dentro desses Environments.
- **Branches**: proteja a `main` (exigir PR). Quem pode alterar um workflow pode ler os secrets que ele usa.
- Nunca adicione `pull_request_target` nem gatilhos automáticos a um workflow que use secrets.

## Cuidados com o que é público
- **Os logs são públicos.** Um build ou deploy pode imprimir nomes de arquivo, trechos de código numa mensagem de erro, nomes de migrations e, quando uma migration falha, parte do SQL. Rode `dry_run` no deploy do Supabase antes e trate um log de falha como legível por qualquer pessoa.
- **Artefatos e logs deste repositório são públicos** (qualquer conta do GitHub baixa um artefato). O GitHub mascara segredos só no **log**, nunca dentro de um arquivo: por isso o `e2e/scrub_artifacts.py` limpa a senha da conta E2E e tokens de sessão de todo arquivo de texto antes do upload, e apaga imagem/vídeo que contenha a senha. O vídeo e as capturas do iOS/Android mostram a tela do app: **use uma conta E2E dedicada, sem dado real e com senha que só serve para isso** (nunca a conta de uso).
- **O APK publicado é um build de debug (`debuggable`) assinado com a chave fixa** quando `ANDROID_KEYSTORE_BASE64` existe. Se essa for a mesma chave de uma loja, esse APK público pode atualizar ou substituir o app real em quem o instalar: use uma chave separada para builds públicos. Por isso `publish_release` exige marcar `public_release_ack`.
- **`DIALETTO_DEPLOY_KEY`**: prefira uma deploy key SSH somente leitura. Um token (PAT) funciona, mas o script não consegue provar que ele só lê (o GitHub não informa os escopos de um token); se usar, que seja fine-grained, só deste repositório, com Contents: read-only.
- **Ações de terceiros por tag, não por SHA** (exceto `android-emulator-runner`). Fixar por SHA (ex.: `pinact` ou Dependabot) é um passo pendente.
- **A Release é pública.** O APK contém o bundle (o mesmo que o site já serve, sem sourcemaps), o shell nativo, o `google-services.json` e a chave publicável do Supabase: nada secreto. Publique **só o APK**, nunca iOS, keystore ou `.p8`. A descrição da Release leva só o número do build, o hash curto do commit e o checksum.
- O APK é de **debug** e é assinado com a chave fixa: é para testar, não é uma release oficial.

## Regras
- **TestFlight só por ordem explícita do dono do projeto.** Cada build manda e-mails da Apple a quem testa; vários ajustes pequenos viram um build, não um por ajuste.
- Mudança de plugin, entitlement, `Info.plist`, `capacitor.config.ts` etc. precisa de build novo; o resto vai por OTA. Veja `docs/OTA_OU_BUILD.md` no repositório do app.

## Para o Claude (agente)
Com acesso a este repositório, o agente pode disparar os workflows e ler os resultados pela API do GitHub (`run_workflow`, logs de job, artefatos), então consegue rodar o E2E, ler o resumo e os screenshots, ajustar os fluxos e rodar de novo, sem depender de ninguém com o aparelho. Ele **não** dispara `ios-testflight` por conta própria.

## Problemas comuns
- **`This token can WRITE` no checkout, mesmo com `Contents: Read-only`**: versões antigas do script confundiam o papel da conta no repositório com o escopo do token. Use a versão atual do workflow; mantenha o token limitado ao `dialetto` com `Contents: Read-only`. Não aumente permissões para resolver esse erro.
- **`error in libcrypto` / `Permission denied (publickey)` no checkout**: o secret `DIALETTO_DEPLOY_KEY` chegou **malformado** (típico ao copiar de um editor do Windows: quebras `\r\n` ou falta da quebra de linha final). O script `scripts/checkout-private-source.sh` repara esses casos e, quando não dá, diz o motivo no log: chave **pública** colada por engano, chave **com senha** (gere com `-N ""`) ou arquivo incompleto. O log também mostra o **fingerprint** da chave; confira que ele é o mesmo que o GitHub mostra em *Deploy keys* do `dialetto`. Se o editor insistir em estragar a chave, guarde no secret o **base64 do arquivo** (`base64 -w0 dialetto-builds-key`; no PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("dialetto-builds-key"))`): o script aceita os dois formatos.
- **`Permission denied (publickey)` com a chave legível** (o log mostra o fingerprint): a chave pública não está em *Deploy keys* do `dialetto`, ou está em outro repositório.
- **`build.gradle no longer reads GITHUB_RUN_NUMBER`**: o app mudou a forma de ler o `versionCode`; ajuste o passo "Point versionCode at the build number" em `_android-apk.yml`.
- **TestFlight recusa o build por número repetido ou menor**: aumente `BUILD_NUMBER_OFFSET`.
- **O app instalado não atualiza por cima do APK novo**: o número do build é menor que o instalado ou a assinatura é diferente (chave de debug em vez do `.jks`).
