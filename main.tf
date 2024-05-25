terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "5.27.0"
    }
  }
}

provider "google" {
  project     = "project-armaggaden-may11"
  region      = "us-central1"
  zone        = "us-central1-a"
  credentials = file("project-armaggaden-may11-2cff6047c441.json")
}

provider "google-beta" {
  project     = "project-armaggaden-may11"
  region      = "us-central1"
  zone        = "us-central1-a"
  credentials = file("project-armaggaden-may11-2cff6047c441.json")
}

resource "google_compute_network" "vpc" {
  name                  = "vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "us-central1a-subnet" {
  name          = "us-central1a-subnet"
  network       = google_compute_network.vpc.self_link
  ip_cidr_range = "10.121.2.0/24"
  region        = "us-central1"
  private_ip_google_access = true
}

resource "google_compute_firewall" "allow-icmp" {
  name    = "icmp-test-firewall"
  network = google_compute_network.vpc.self_link

  allow {
    protocol = "icmp"
  }
  source_ranges = ["0.0.0.0/0"]
  priority      = 600
}

resource "google_compute_firewall" "allow-http" {
  name    = "allow-http"
  network = google_compute_network.vpc.self_link

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
  source_ranges = ["0.0.0.0/0"]
  priority      = 100
}

resource "google_compute_firewall" "allow-https" {
  name    = "allow-https"
  network = google_compute_network.vpc.self_link

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }
  source_ranges = ["0.0.0.0/0"]
  priority      = 100
}

resource "google_compute_instance_template" "instance-template" {
  name = "romulus-server"
  description = "romulus-server"
  labels = {
    environment = "production"
    name = "romulus-server"
  }
  instance_description = "this is an instance that has been autochaled"
  machine_type = "e2-medium"
  can_ip_forward = false

  scheduling {
    automatic_restart = true
    on_host_maintenance = "MIGRATE"
  }
  disk {
    source_image = "debian-cloud/debian-12"
    auto_delete = true
    boot = true
  }
  disk {
    auto_delete = false
    disk_size_gb = 10
    mode = "READ_WRITE"
    type = "PERSISTENT"
  }
  network_interface {
    network    = google_compute_network.vpc.self_link
    subnetwork = google_compute_subnetwork.us-central1a-subnet.self_link

    access_config {
      // Ephemeral IP
    }
  }

  tags = ["http-server"]

  metadata_startup_script = file("startup.sh")

  depends_on = [
    google_compute_network.vpc,
    google_compute_subnetwork.us-central1a-subnet,
    google_compute_firewall.allow-http
  ]
}

resource "google_compute_health_check" "health-check05" {
  count = 1
  name               = "http-basic-check"
  check_interval_sec = 5
  timeout_sec        = 5
  healthy_threshold  = 2
  unhealthy_threshold = 10

  http_health_check {
    request_path = "/"
    port = "80"
  }
}

resource "google_compute_region_instance_group_manager" "region-instance-group" {
  name = "instance-group82"

  base_instance_name         = "app"
  region                     = "us-central1"
  distribution_policy_zones  = ["us-central1-a", "us-central1-f"]

  version {
    instance_template = google_compute_instance_template.instance-template.id
  }

  named_port {
    name = "custom"
    port = 80
  }
}

resource "google_compute_region_autoscaler" "autoscaler" {
  name    = "autoscaler"
  project = "project-armaggaden-may11"
  region  = "us-central1"
  target  = google_compute_region_instance_group_manager.region-instance-group.self_link

  autoscaling_policy {
    max_replicas      = 6
    min_replicas      = 3
    cooldown_period   = 60
    cpu_utilization {
      target = 0.6
    }
  }
}

resource "google_compute_address" "loadbalancer-ip" {
  name         = "website-ip-1"
  provider     = google-beta 
  region       = "us-central1"
  network_tier = "STANDARD"
}

resource "google_compute_region_target_http_proxy" "proxy-sub01" {
  provider = google-beta

  region  = "us-central1"
  name    = "website-proxy"
  url_map = google_compute_region_url_map.default.id
}

resource "google_compute_subnetwork" "proxy" {
  provider = google-beta
  name          = "website-net-proxy"
  ip_cidr_range = "10.129.0.0/26"
  region        = "us-central1"
  network       = google_compute_network.vpc.id
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
}

resource "google_compute_forwarding_rule" "load-balancer82" {
  provider = google-beta
  depends_on = [
    google_compute_region_target_http_proxy.proxy-sub01,
    google_compute_subnetwork.proxy
  ]
  name   = "website-forwarding-rule"
  region = "us-central1"

  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "80"
  target                = google_compute_region_target_http_proxy.proxy-sub01.id
  network               = google_compute_network.vpc.id
  ip_address            = google_compute_address.loadbalancer-ip.address
  network_tier          = "STANDARD"
}

resource "google_compute_region_url_map" "default" {
  provider = google-beta

  region          = "us-central1"
  name            = "website-map"
  default_service = google_compute_region_backend_service.default.id
}

resource "google_compute_region_backend_service" "default" {
  provider = google-beta

  load_balancing_scheme = "EXTERNAL_MANAGED"

  backend {
    group           = google_compute_region_instance_group_manager.region-instance-group.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }

  region      = "us-central1"
  name        = "website-backend"
  protocol    = "HTTP"
  timeout_sec = 10

  health_checks = [google_compute_region_health_check.region-health-check06.id]
}

data "google_compute_image" "debian_image" {
  provider = google-beta
  family   = "debian-12"
  project  = "debian-cloud"
}

resource "google_compute_region_health_check" "region-health-check06" {
  depends_on = [google_compute_firewall.allow-https]
  provider = google-beta

  region = "us-central1"
  name   = "website-hc"
  http_health_check {
    port_specification = "USE_SERVING_PORT"
  }
}

resource "google_compute_firewall" "fw1" {
  provider = google-beta
  name     = "website-fw-1"
  network  = google_compute_network.vpc.id
  source_ranges = ["10.1.2.0/24"]
  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }
  direction = "INGRESS"
}

resource "google_compute_firewall" "fw2" {
  depends_on = [google_compute_firewall.fw1]
  provider = google-beta
  name     = "website-fw-2"
  network  = google_compute_network.vpc.id
  source_ranges = ["0.0.0.0/0"]
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  target_tags = ["allow-ssh"]
  direction = "INGRESS"
}

resource "google_compute_firewall" "fw3" {
  depends_on = [google_compute_firewall.fw2]
  provider = google-beta
  name     = "website-fw-3"
  network  = google_compute_network.vpc.id
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  allow {
    protocol = "tcp"
  }
  target_tags = ["load-balanced-backend"]
  direction = "INGRESS"
}

resource "google_compute_firewall" "fw4" {
  depends_on = [google_compute_firewall.fw3]
  provider = google-beta
  name     = "website-fw-4"
  network  = google_compute_network.vpc.id
  source_ranges = ["10.129.0.0/26"]
  target_tags = ["load-balanced-backend"]
  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
  allow {
    protocol = "tcp"
    ports    = ["443"]
  }
  allow {
    protocol = "tcp"
    ports    = ["8000"]
  }
  direction = "INGRESS"
}


