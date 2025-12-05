# Production environment variable configuration
# This file contains production-specific values for the Terraform deployment
# IMPORTANT: Do not commit sensitive values to version control
# Consider using environment variables or secret management tools for sensitive data

# GCP Project Configuration
# Replace with your actual GCP project ID
# You can find this in the GCP Console or by running: gcloud config get-value project
project_id = "your-gcp-project-id"

# Region Configuration
# us-central1 offers good GPU availability and competitive pricing
# Alternative regions: us-west1, us-east1, europe-west4 (check GPU availability)
region = "us-central1"

# Environment Identifier
# Used as a prefix for all resources to distinguish from dev/staging environments
# This helps with resource organization and cost tracking
environment = "prod"
