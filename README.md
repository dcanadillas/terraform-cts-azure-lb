# Example CTS module for Azure Load Balancing

This is a Terraform Module to use with [Consul Terrraform Sync](https://developer.hashicorp.com/consul/tutorials/network-infrastructure-automation/consul-terraform-sync-intro) to create Azure Load Balancers than points to the instances of the services created or modified in Consul.

*This is a demo repo that is not Production ready and could have bugs for specific scenarios.*

WIP...

## Requirements

To create the load balancers required from the services data in Consul we are using some [Service Meta Data](https://developer.hashicorp.com/consul/docs/discovery/services#adding-meta-data) tags that are defined in the services from the Consul Service Catalog:

```
...
"ServiceMeta": {
  "azure_vm": "client-vm-0",
  "external-source": "nomad",
  "hostname": "client-vm-0",
  "location": "westeurope",
  "resource_group": "dcanadillas-consul"
},
...
```
## Alternatives for Service Meta

Also, [Node Meta](https://developer.hashicorp.com/consul/docs/agent/config/config-files#node_meta) in Consul could be used, because the information needed for Terraform to deploy the Azure load balancers and configure the security rules for inbound rules is associated to the node information, like `virtual machine name`, `network interface ids`, `location` or `resource groups`. This information is also injected from Consul Terraform Sync, so we could develop our Terraform module to realy on that data.

In this scenario that metadata should be added on the Consul nodes when deploying Consul

## Why using Service Meta in our case

In our demo examples (not included in this repo) we are using Nomad to deploy and run the applications that are registered as services in Consul, and in that case Nomad is able to inject some [runtime node variables](https://developer.hashicorp.com/nomad/docs/runtime/interpolation#interpreted_node_vars), like the information of the Azure attributes of the VM. Below there is an basic example of a nomad job that would inject that metadata:

```
job "back" {
  datacenters = ["${var.datacenter}"]

  group "back" {
    network {
      port "back" {
        to = 9090
      }
      mode = "bridge"
    }
    service {
      name = "backend"
      tags = ["backend", "python"]
      meta {
        hostname = "${attr.unique.hostname}"
        resource_group = "${attr.platform.azure.resource-group}"
        location = "${attr.platform.azure.location}"
        azure_vm = "${attr.unique.platform.azure.name}"
        resource_group = "${attr.platform.azure.resource-group}"
      }
      port = 9090
      connect {
        sidecar_service {}
      }
    }

    task "back" {
      driver = "docker"

      config {
        image = "hcdcanadillas/pydemo-back:v1.1-amd64"
        ports = ["back"]
      }
      env {
        PORT = "$${NOMAD_PORT_back}"
      }
    }
  }
}
```

