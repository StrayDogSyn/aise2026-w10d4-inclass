# Terraform configuration block
# Defines required providers and backend configuration for state management
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
  
  # Backend configuration for remote state storage in Google Cloud Storage
  # This enables team collaboration and state locking to prevent concurrent modifications
  # The backend block allows storing Terraform state remotely for production use
  backend "gcs" {
    bucket = "your-terraform-state-bucket"  # Replace with your GCS bucket name
    prefix = "terraform/state"               # Path prefix within the bucket
  }
}

# Google Cloud provider configuration
# Authenticates and configures the GCP project and default region for all resources
provider "google" {
  project = var.project_id
  region  = var.region
}

# Virtual Private Cloud (VPC) network for ML infrastructure
# Creates an isolated network environment for the GKE cluster
# auto_create_subnetworks is disabled to allow manual subnet configuration for better control
resource "google_compute_network" "ml_vpc" {
  name                    = "${var.environment}-ml-vpc"
  auto_create_subnetworks = false
}

# Subnet within the VPC for GKE cluster nodes
# Provides IP address range for pods and services within the cluster
# Using a /16 CIDR block provides ~65,000 IP addresses for scalability
resource "google_compute_subnetwork" "ml_subnet" {
  name          = "${var.environment}-ml-subnet"
  ip_cidr_range = "10.0.0.0/16"
  region        = var.region
  network       = google_compute_network.ml_vpc.id
}
# Google Kubernetes Engine (GKE) cluster for ML workloads
# Regional cluster provides high availability across multiple zones
# Default node pool is removed to allow custom node pool configurations
resource "google_container_cluster" "ml_cluster" {
  name     = "${var.environment}-ml-cluster"
  location = var.region

  # Remove default node pool to create custom pools (CPU and GPU)
  # Initial node count of 1 is required but will be immediately deleted
  remove_default_node_pool = true
  initial_node_count       = 1

  # Connect cluster to the custom VPC and subnet
  network    = google_compute_network.ml_vpc.name
  subnetwork = google_compute_subnetwork.ml_subnet.name

  # Enable Workload Identity for secure service account authentication
  # Allows pods to authenticate as GCP service accounts without key files
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
}

# CPU node pool for general-purpose workloads
# Handles API servers, data preprocessing, and non-GPU tasks
# Uses cost-effective machine types suitable for standard computational workloads
resource "google_container_node_pool" "cpu_pool" {
  name       = "cpu-pool"
  location   = var.region
  cluster    = google_container_cluster.ml_cluster.name
  node_count = 2  # Initial node count before autoscaling kicks in

  node_config {
    # n1-standard-4: 4 vCPUs, 15 GB memory - balanced for general workloads
    # Good price-to-performance ratio for CPU-bound tasks
    machine_type = "n1-standard-4"
    
    # 50 GB disk sufficient for OS, container images, and temporary storage
    disk_size_gb = 50
    disk_type    = "pd-standard"  # Standard persistent disk for cost efficiency

    # OAuth scopes grant permissions for GCP API access
    # cloud-platform scope provides full access to all GCP services
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    # Labels for workload identification and node selection
    labels = {
      workload = "general"
    }
    
    # Metadata to ensure nodes are properly configured
    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  # Autoscaling configuration for dynamic resource allocation
  # Automatically adjusts node count based on workload demands
  autoscaling {
    min_node_count = 1   # Minimum nodes to keep running (cost optimization)
    max_node_count = 10  # Maximum nodes for peak loads (prevents runaway costs)
  }
}

# GPU node pool for machine learning training and inference
# Dedicated pool with NVIDIA Tesla T4 GPUs for compute-intensive ML workloads
# Starts with 0 nodes and scales based on demand to minimize costs
resource "google_container_node_pool" "gpu_pool" {
  name       = "gpu-pool"
  location   = var.region
  cluster    = google_container_cluster.ml_cluster.name
  node_count = 0  # Start with 0 nodes, scale up when GPU workloads are scheduled

  node_config {
    # n1-standard-4: 4 vCPUs, 15 GB memory - adequate for GPU workloads
    # Machine type must support GPU attachment
    machine_type = "n1-standard-4"
    
    # 100 GB disk for larger ML models, datasets, and checkpoints
    disk_size_gb = 100
    disk_type    = "pd-standard"

    # GPU accelerator configuration
    # NVIDIA Tesla T4: Cost-effective GPU for training and inference
    # Provides 16GB GPU memory with mixed-precision capabilities
    guest_accelerator {
      type  = "nvidia-tesla-t4"
      count = 1  # One GPU per node
      
      # GPU driver installation mode
      # Latest driver installation is handled by GKE
      gpu_driver_installation_config {
        gpu_driver_version = "LATEST"
      }
    }

    # OAuth scopes for GCP service access
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    # Labels for node identification and pod scheduling
    labels = {
      workload = "gpu-training"
    }
    
    # Metadata configuration
    metadata = {
      disable-legacy-endpoints = "true"
    }

    # Taints prevent non-GPU workloads from being scheduled on expensive GPU nodes
    # A taint is a node property that repels pods unless they have matching tolerations
    # This ensures only pods that explicitly request GPUs run on these nodes
    # Prevents accidental scheduling of CPU workloads on costly GPU infrastructure
    taint {
      key    = "nvidia.com/gpu"
      value  = "present"
      effect = "NoSchedule"  # Pods without toleration won't be scheduled here
    }
  }

  # Autoscaling for GPU nodes - conservative limits due to high cost
  # GPU nodes are expensive, so we scale carefully
  autoscaling {
    min_node_count = 0  # Scale to zero when no GPU workloads (cost savings)
    max_node_count = 5  # Limit maximum GPU nodes to control costs
  }
}

# Output: GKE cluster endpoint (API server URL)
# Used for kubectl configuration and cluster access
# Marked sensitive to prevent exposure in logs
output "cluster_endpoint" {
  description = "GKE cluster API endpoint for kubectl access"
  value       = google_container_cluster.ml_cluster.endpoint
  sensitive   = true
}

# Output: Cluster CA certificate for secure TLS communication
# Required for authenticating kubectl connections to the cluster
# Base64 decoded for direct use in kubeconfig
output "cluster_ca_certificate" {
  description = "Base64 decoded cluster CA certificate for secure communication"
  value       = base64decode(google_container_cluster.ml_cluster.master_auth[0].cluster_ca_certificate)
  sensitive   = true
}

# Output: Cluster name for reference in other configurations
output "cluster_name" {
  description = "Name of the GKE cluster"
  value       = google_container_cluster.ml_cluster.name
}

# Output: VPC network name for networking configurations
output "vpc_network" {
  description = "Name of the VPC network hosting the cluster"
  value       = google_compute_network.ml_vpc.name
}
