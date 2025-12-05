# GCP Project ID Variable
# This is the unique identifier for your Google Cloud Platform project
# Required for all GCP resource provisioning
# Example: "my-ml-project-12345"
variable "project_id" {
  description = "GCP project ID where all infrastructure resources will be created"
  type        = string
  
  validation {
    condition     = length(var.project_id) > 0
    error_message = "Project ID must not be empty. Provide a valid GCP project ID."
  }
}

# GCP Region Variable
# Determines the geographic location for the GKE cluster and associated resources
# Regional deployment provides high availability across multiple zones
# Choose a region with GPU availability for the ML workloads
variable "region" {
  description = "GCP region for deploying the GKE cluster and associated resources. Choose a region with GPU availability (e.g., us-central1, us-west1, europe-west4)"
  type        = string
  default     = "us-central1"
  
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "Region must be a valid GCP region format (e.g., us-central1, europe-west4)."
  }
}

# Environment Variable
# Used as a naming prefix for all resources to distinguish between environments
# Enables parallel deployment of dev, staging, and production infrastructures
# Also facilitates cost tracking and resource organization by environment
variable "environment" {
  description = "Environment identifier (dev/staging/prod) used for resource naming and organization. This prefix helps distinguish resources across different deployment stages."
  type        = string
  
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}
