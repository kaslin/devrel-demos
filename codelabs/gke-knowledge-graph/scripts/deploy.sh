#!/bin/bash
# Copyright 2026 Google LLC
# ... [License Header Preserved] ...

echo "🚀 Starting Petverse Deployment (Modern Workload Identity)..."

# Load environment variables
ENV_FILE="$(dirname "$0")/../.env"
if [ -f "$ENV_FILE" ]; then
    echo "Loading environment from $ENV_FILE..."
    export $(cat "$ENV_FILE" | xargs)
fi

# Check for Project ID & Region
if [ -z "$PROJECT_ID" ]; then
    read -p "Enter your Google Cloud Project ID: " PROJECT_ID
fi
if [ -z "$PROJECT_ID" ]; then
    echo "❌ Project ID cannot be empty."
    exit 1
fi

if [ -z "$REGION" ]; then
    read -p "Enter your Region (e.g., us-central1) [default: us-central1]: " REGION
fi
REGION=${REGION:-us-central1}

# --- NEW: Get Project Number for the Principal ID ---
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
KSA_NAME="petverse-gke-sa"
KSA_NAMESPACE="default"

# This is the modern Principal identifier for your Kubernetes Service Account
KSA_PRINCIPAL="principal://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${PROJECT_ID}.svc.id.goog/subject/ns/${KSA_NAMESPACE}/sa/${KSA_NAME}"

if [ ! -f "job-producer.yaml" ] || [ ! -f "job-worker.yaml" ]; then
    echo "❌ job-producer.yaml or job-worker.yaml not found. Please run scripts/setup.sh first."
    exit 1
fi

# --- UPDATED: Grant IAM roles DIRECTLY to the KSA principal ---
echo "🔐 Granting IAM roles directly to Kubernetes Service Account..."

ROLES=(
    "roles/aiplatform.user"
    "roles/bigquery.dataEditor"
    "roles/bigquery.user"
    "roles/storage.objectViewer"
    "roles/pubsub.publisher"
    "roles/pubsub.subscriber"
)

for ROLE in "${ROLES[@]}"; do
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="$KSA_PRINCIPAL" \
        --role="$ROLE" \
        --condition=None >/dev/null
done

# --- UPDATED: Configuring K8s Service Account (No annotation needed!) ---
echo "🔐 Creating K8s Service Account..."
kubectl create serviceaccount $KSA_NAME 2>/dev/null || echo "ℹ️ Service account $KSA_NAME already exists."

echo "📊 Loading sample data into BigQuery..."
bq mk --dataset --location=$REGION $PROJECT_ID:petverse_kg 2>/dev/null || echo "ℹ️ Dataset petverse_kg already exists."

bq load --source_format=CSV --autodetect --replace petverse_kg.pets gs://sample-data-and-media/petverse/pets.csv
bq load --source_format=CSV --autodetect --replace petverse_kg.pet_urls gs://sample-data-and-media/petverse/pet_urls.csv

echo "🎉 🦄 👉 Deployment configured successfully with Direct Resource Access!"
echo "👉 You can now run the jobs manually:"
echo "   1. Populate the queue:  kubectl apply -f job-producer.yaml"
echo "   2. Process in parallel: kubectl apply -f job-worker.yaml"