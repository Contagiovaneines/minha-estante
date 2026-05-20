# Configuracao de assinatura para release Android

Este guia precisa ser seguido uma vez antes de publicar na Play Store.

Nunca comite os arquivos gerados aqui. O `.gitignore` ja bloqueia `android/key.properties`, `*.jks` e `*.keystore`.

## 1. Gerar a upload key

Execute no PowerShell:

```powershell
keytool -genkey -v `
  -keystore "$env:USERPROFILE\upload-keystore.jks" `
  -storetype JKS `
  -keyalg RSA `
  -keysize 2048 `
  -validity 10000 `
  -alias upload
```

Voce sera perguntado sobre:

- Senha do keystore: escolha uma senha forte e guarde em um gerenciador de senhas.
- Nome, organizacao, cidade, estado e pais: preencha com seus dados de desenvolvedor.

O arquivo `upload-keystore.jks` sera criado na pasta do seu usuario.

Guarde esse arquivo e a senha. Sem a chave correta, voce pode perder a capacidade de enviar atualizacoes assinadas corretamente.

## 2. Criar `android/key.properties`

Copie `android/key.properties.example` para `android/key.properties` e preencha:

```properties
storePassword=SUA_SENHA_DO_KEYSTORE
keyPassword=SUA_SENHA_DO_KEYSTORE
keyAlias=upload
storeFile=C:/Users/SEU_USUARIO/upload-keystore.jks
```

Substitua:

- `SUA_SENHA_DO_KEYSTORE` pela senha escolhida.
- `SEU_USUARIO` pelo seu usuario do Windows.

## 3. Como o Gradle usa a chave

O `android/app/build.gradle.kts` ja esta configurado para ler `android/key.properties`.

- Se `android/key.properties` existir e estiver completo, o build `release` usa a keystore real.
- Se ele nao existir, o projeto usa fallback de assinatura debug apenas para desenvolvimento local.

Para Play Store, sempre gere o AAB com `android/key.properties` configurado.

## 4. Gerar AAB assinado para Play Store

```bash
flutter build appbundle --release
```

Arquivo gerado:

```text
build/app/outputs/bundle/release/app-release.aab
```

Esse e o arquivo que voce envia para o Play Console.

## 5. Instalar sem Play Store

Para usar no celular antes de publicar, gere um APK:

```bash
flutter build apk --release
```

Arquivo gerado:

```text
build/app/outputs/flutter-apk/app-release.apk
```

Instale manualmente no aparelho. O Android pode pedir para liberar "instalar apps desconhecidos" para o app que abrir o APK.

## 6. Play App Signing

No Play Console:

1. Crie o app com o package name `com.minhaestante.minha_estante`.
2. Aceite os termos do Play App Signing.
3. Envie o AAB assinado.
4. Para app novo, normalmente o Google gera e protege a chave final de assinatura.
5. Sua upload key local fica sendo usada para assinar proximas versoes antes do upload.

## 7. Notas importantes

- O package name nao pode ser trocado depois da publicacao sem criar outro app.
- Use o mesmo package name nos testes internos e na producao.
- Aumente o `versionCode` a cada novo envio para a Play Store.
- Guarde a keystore e a senha em locais seguros.
- Ative verificacao em duas etapas na conta Google usada no Play Console.
- A politica de privacidade publica precisa estar online antes de enviar o app para revisao.
