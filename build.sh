#!/bin/bash
set -e

echo "🚀 Starting Flutter Web Build..."

# 1. Clone Flutter stable if not already cloned (using shallow clone for maximum speed)
if [ ! -d "flutter" ]; then
  echo "📦 Cloning Flutter stable SDK (shallow clone)..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1
fi

# 2. Setup environment variables from Cloudflare Pages environment
echo "🔑 Generating .env file..."
cat <<EOF > .env
OLA_MAPS_API_KEY=${OLA_MAPS_API_KEY}
SUPABASE_URL=${SUPABASE_URL}
SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}
ADMIN_SECRET=${ADMIN_SECRET}
EOF

# 3. Build Flutter Web Release (CanvasKit/Skwasm is automatically used in modern Flutter)
echo "🛠️ Building Flutter Web (Release)..."
./flutter/bin/flutter config --no-analytics
./flutter/bin/flutter build web --release

echo "✅ Build completed successfully! Output directory: build/web"

