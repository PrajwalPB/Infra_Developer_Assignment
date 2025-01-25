provider "kubernetes" {
  config_path = "~/.kube/config" # Adjust to your kubeconfig path
}

# Load JSON data
data "template_file" "applications_json" {
  template = file("${path.module}/applications.json")
}

data "jsondecode" "applications" {
  content = data.template_file.applications_json.rendered
}

# Iterate over applications and create Kubernetes resources
resource "kubernetes_deployment" "apps" {
  for_each = { for app in data.jsondecode.applications.applications : app.name => app }

  metadata {
    name = each.key
    labels = {
      app = each.key
    }
  }

  spec {
    replicas = each.value.replicas

    selector {
      match_labels = {
        app = each.key
      }
    }

    template {
      metadata {
        labels = {
          app = each.key
        }
      }
      spec {
        container {
          name  = each.key
          image = each.value.image

          args = split(" ", each.value.args)

          ports {
            container_port = each.value.port
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "apps" {
  for_each = kubernetes_deployment.apps

  metadata {
    name = each.key
    labels = {
      app = each.key
    }
  }

  spec {
    selector = {
      app = each.key
    }

    port {
      protocol    = "TCP"
      port        = each.value.spec.template.spec[0].ports[0].container_port
      target_port = each.value.spec.template.spec[0].ports[0].container_port
    }
  }
}

# Ingress for blue app
resource "kubernetes_ingress" "blue_ingress" {
  metadata {
    name = "blue-ingress"
    annotations = {
      "nginx.ingress.kubernetes.io/rewrite-target" : "/"
    }
  }

  spec {
    rules {
      host = "testapp.com"
      http {
        paths {
          path     = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.apps["foo"].metadata[0].name
              port {
                number = kubernetes_service.apps["foo"].spec[0].port[0].port
              }
            }
          }
        }
      }
    }
  }
}

# Ingress for green app with traffic splitting
resource "kubernetes_ingress" "green_ingress" {
  metadata {
    name = "green-ingress"
    annotations = {
      "nginx.ingress.kubernetes.io/rewrite-target" : "/"
      "nginx.ingress.kubernetes.io/canary"        : "true"
      "nginx.ingress.kubernetes.io/canary-weight" : "30"
    }
  }

  spec {
    rules {
      host = "testapp.com"
      http {
        paths {
          path     = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.apps["bar"].metadata[0].name
              port {
                number = kubernetes_service.apps["bar"].spec[0].port[0].port
              }
            }
          }
        }
      }
    }
  }
}
