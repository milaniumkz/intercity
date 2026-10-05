#!/bin/bash
set -e

echo "=== INTERCITY Cloud Run Deployment ==="

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    echo "Error: gcloud CLI not found. Install Google Cloud SDK."
    exit 1
fi

# Set project
PROJECT_ID=${1:-$(gcloud config get-value project)}
if [ -z "$PROJECT_ID" ]; then
    echo "Error: Please specify project ID or set default"
    exit 1
fi

echo "Project: $PROJECT_ID"

# Database URL (you need to provide this)
if [ -z "$DATABASE_URL" ]; then
    echo "DATABASE_URL not set. Please provide your Cloud SQL connection string."
    echo "Format: postgresql://user:password@/cloudsql/project:region:instance"
    exit 1
fi

# Build and deploy
echo "Building backend..."
cd backend
npm install
npm run build
npx prisma generate

echo "Deploying to Cloud Run..."
gcloud run deploy intercity-backend \
    --source . \
    --region us-central1 \
    --platform managed \
    --allow-unauthenticated \
    --set-env-vars "DATABASE_URL=$DATABASE_URL,JWT_SECRET=$JWT_SECRET,JWT_REFRESH_SECRET=$JWT_REFRESH_SECRET,OSRM_URL=http://router.project-osrm.org,NOMINATIM_URL=https://nominatim.openstreetmap.org,YANDEX_GEOCODER_API_KEY=${YANDEX_GEOCODER_API_KEY:-},KASSA24_FUNCTION_URL=${KASSA24_FUNCTION_URL:-https://us-central1-inter-city-pkzpps.cloudfunctions.net/kassa24},CORS_ORIGINS=${CORS_ORIGINS:-*},PORT=8080"

echo "=== Deployment Complete ==="
echo "Your API is now available at:"
gcloud run services describe intercity-backend --platform managed --region us-central1 --format 'value(status.url)'
