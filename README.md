# EduVerse AI

Yapay zekâ destekli, oyunlaştırılmış kişisel öğrenme platformu. Duolingo tarzı dersler,
seriler ve XP; dillerden programlamaya geniş bir katalog.

> **Durum:** Faz 1 tamamlandı — çalışan dikey dilim: kayıt → giriş → onboarding → kurs listesi →
> ders → ilerleme kaydı. Ayrıntılar: [documentation/ROADMAP.md](documentation/ROADMAP.md)

## APK indir

En son derleme: **[eduverse-ai.apk](../../releases/latest/download/eduverse-ai.apk)**
(her `main` push'unda GitHub Actions derler).

APK varsayılan olarak **çevrimdışı modda** çalışır: içerik uygulamanın içinde gelir, hesap ve
ilerleme cihazda saklanır. Sunucuya bağlı sürüm için depo ayarlarında
`Settings → Secrets and variables → Actions → Variables` altına `API_BASE_URL` ekleyin.

## Yapı

```
apps/api         NestJS + Prisma + PostgreSQL backend
apps/mobile      Flutter (Android / iOS)
apps/admin       Yönetim paneli (Faz 7)
packages/content Kurs içerik paketi (seed + çevrimdışı uygulama)
infrastructure   Docker geliştirme ortamı
documentation    Mimari ve yol haritası
```

Mimari: [documentation/ARCHITECTURE.md](documentation/ARCHITECTURE.md)

## Backend'i çalıştır

```bash
docker compose -f infrastructure/docker/docker-compose.yml up -d postgres redis
cd apps/api
cp .env.example .env            # JWT_ACCESS_SECRET'i değiştir
npm install
npx prisma migrate deploy
npm run seed
npm run start:dev               # http://localhost:3000/health
npm test && npm run test:e2e    # e2e için veritabanı gerekir
```

## Mobil uygulamayı çalıştır

```bash
cd apps/mobile
flutter create --platforms=android,ios --org ai.eduverse --project-name eduverse_ai .
rm -f test/widget_test.dart
cp ../../packages/content/courses.json assets/content/courses.json
flutter pub get
flutter run                                                  # çevrimdışı mod
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000  # Android emülatörden yerel API
flutter test
```

`android/` ve `ios/` klasörleri şimdilik `flutter create` ile üretiliyor; native ayar
gerektiğinde depoya eklenecek.

## Güvenlik ilkeleri

Cevap anahtarları istemciye gönderilmez; puanlama, XP, seri ve kilit açma sunucuda hesaplanır.
API anahtarları yalnızca sunucuda durur. Ayrıntılar mimari dokümanında.
