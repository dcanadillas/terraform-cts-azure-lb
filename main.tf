terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.11.0"
    }
    azuread = {
      source = "hashicorp/azuread"
      version = "2.25.0"
    }
  }
}

provider "azurerm" {
  features {}
}

locals {
  consul_service_ids = transpose({
    for id, s in var.services : id => [s.name]
  })
  consul_services = {
    for name, ids in local.consul_service_ids : name => [for id in ids : var.services[id]]
  }
  service_addresses = [ for s in var.services : s.address ]
  # List of resources groups of the services
  # resource_groups = distinct([for a,s in var.services : data.azurerm_resource_group.main[a].name])
  resource_groups = transpose({ for id, se in var.services : id => [se.meta.resource_group]})
  rg_services = { for rg,ids in local.resource_groups : rg => [ for id in ids : var.services[id]]}
  # Grouping ports for resource groups
  # group_ports = {for a,b in var.services : b.id => b.port...}
  group_ports = { for rg,ports in {for a,b in var.services : data.azurerm_resource_group.main[a].name => b.port...} : rg => distinct(ports) }
  services_unique_ports = { for service,data in local.consul_services : service => coalesce(distinct(data[*].port)) }
  # Map of vm ==> rg
  vms = distinct([ for i in var.services : { vms = i.meta.azure_vm, rgs = i.meta.resource_group} ])
  # It should be one security group 
  security_group = distinct([ for i in data.azurerm_network_interface.main : i.network_security_group_id ])
  lb_name = [ for i in var.services : i.node_datacenter ]
}


data "azurerm_resource_group" "main" {
  for_each = var.services
  # The resource group is included from Nomad deployment in the service as a node metadata in Consul
  name = each.value.meta.resource_group
}

data "azurerm_network_interface" "main" {
  count = length(local.vms)
  name                = "consul-client-nic-${regex("\\d$",local.vms[count.index].vms)}"
  resource_group_name = local.vms[count.index].rgs
}

module "lb" {
  count = local.consul_services != {} ? 1 : 0
  source = "./modules/load-balancer"

  services = var.services
  network_interfaces = [ for i in data.azurerm_network_interface.main : i.id ]
  # Let's assume that there is only one RG and one location. TODO: probably think on a multi-location scenario
  location = coalesce(distinct([ for i in data.azurerm_resource_group.main : i.location]) ...)
  resource_group = coalesce(distinct([ for i in data.azurerm_resource_group.main : i.name]) ...)
  lb_name = coalesce(local.lb_name ...)
}

module "security_rules" {
  count = local.consul_services != {} ? 1 : 0
  source = "./modules/security-rules"
  # count = length(local.vms)

  services = var.services
  # Let's assume that there is only one RG and one location. TODO: probably think on a multi-location scenario
  location = coalesce(distinct([ for i in data.azurerm_resource_group.main : i.location]) ...)
  resource_group = coalesce(distinct([ for i in data.azurerm_resource_group.main : i.name]) ...)
  security_group_name = coalesce(local.security_group ...)
}


