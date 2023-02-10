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
  services_unique_ports = { for service,data in local.consul_services : service => distinct(data[*].port)[0] }
  # Map of vm ==> rg
  vms = distinct([ for i in var.services : { vms = i.meta.azure_vm, rgs = i.meta.resource_group} ])
  # It should be one security group 
  security_group = distinct([ for i in data.azurerm_network_interface.main : i.network_security_group_id ])[0]
  # priority ={ for i,j in } 
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
  source = "./modules/load-balancer"

  services = var.services
  network_interfaces = [ for i in data.azurerm_network_interface.main : i.id ]
  # Let's assume that there is only one RG and one location. TODO: probably think on a multi-location scenario
  location = distinct([ for i in data.azurerm_resource_group.main : i.location])[0]
  resource_group = distinct([ for i in data.azurerm_resource_group.main : i.name])[0]
  lb_name = [ for i in var.services : i.node_datacenter ][0]
}

module "security_rules" {
  source = "./modules/security-rules"
  # count = length(local.vms)

  services = var.services
  # Let's assume that there is only one RG and one location. TODO: probably think on a multi-location scenario
  location = distinct([ for i in data.azurerm_resource_group.main : i.location])[0]
  resource_group = distinct([ for i in data.azurerm_resource_group.main : i.name])[0]
  security_group_name = basename(local.security_group)
}

# resource "azurerm_network_security_group" "main" {
#   # We iterate for every resource group name obtained in a local variable ( resource_group => [ports])
#   # for_each = local.group_ports
#   # for_each = toset(distinct(flatten([for services in local.consul_services : services[*].meta.resource_group])))
#   for_each = local.rg_services
#   name                = "security-group"
#   location            = "westeurope"
#   resource_group_name = each.key

#   # We need to create a security rule block per every port that comes from the local.group_ports values list
#   dynamic "security_rule" {
#     for_each = local.services_unique_ports
#     content {
#       name                       = security_rule.key
#       # We get the index number from the "for_each" to sum to the priority
#       priority                   = 100 + index([for i,j in local.services_unique_ports : i],security_rule.key)
#       direction                  = "Inbound"
#       access                     = "Allow"
#       protocol                   = "Tcp"
#       source_port_range          = "*"
#       destination_port_range     = security_rule.value
#       source_address_prefix      = "*"
#       destination_address_prefix = "*"
#     }
#   }

#   tags = {
#     environment = "Production"
#   }
# }

# resource "azurerm_network_security_rule" "example" {
#   for_each = local.services_unique_ports
#   name                        = each.key
#   priority                    = 100 + index([for i,j in local.services_unique_ports : i],each.key)
#   direction                  = "Inbound"
#   access                     = "Allow"
#   protocol                   = "Tcp"
#   source_port_range          = "*"
#   destination_port_range     = security_rule.value
#   source_address_prefix      = "*"
#   destination_address_prefix = "*"
#   resource_group_name         = azurerm_resource_group.example.name
#   network_security_group_name = local.security_group
# }

# resource "azurerm_network_interface_security_group_association" "app" {
#   count = length(local.vms)
#   network_interface_id      = data.azurerm_network_interface.main[count.index].id
#   network_security_group_id = azurerm_network_security_group.main[data.azurerm_network_interface.main[count.index].resource_group_name].id
# }

# resource "azurerm_public_ip" "lb" {
#   for_each = local.rg_services
#   name                = each.key
#   location            = element([ for i in each.value : i.meta.location ],0)
#   resource_group_name = element([ for i in each.value : i.meta.resource_group ],0)
#   allocation_method   = "Static"
#   sku                 = "Standard"
#   domain_name_label = "demoapp-${each.key}"
# }

# resource "azurerm_lb" "app" {
#   # We need to create a LB per RG
#   for_each = local.rg_services
#   name                = "lb-${each.key}"
#   # Cloud location for instances are the same, so we take the location from the first instance (element) from the list
#   location            = element([ for i in each.value : i.meta.location ],0)
#   resource_group_name = element([ for i in each.value : i.meta.resource_group ],0)

#   sku = "Standard"

#   frontend_ip_configuration {
#     name                 = "consulconfiguration"
#     public_ip_address_id = azurerm_public_ip.lb["${each.key}"].id
#   }
# }

# resource "azurerm_lb_backend_address_pool" "app" {
#   for_each = azurerm_lb.app
#   loadbalancer_id = azurerm_lb.app[each.key].id
#   name            = "demoapp-${each.value.name}"
# }

# resource "azurerm_network_interface_backend_address_pool_association" "app" {
#   count = length(local.vms)
#   network_interface_id    = data.azurerm_network_interface.main[count.index].id
#   ip_configuration_name   = "consulconfiguration"
#   backend_address_pool_id = azurerm_lb_backend_address_pool.app[data.azurerm_network_interface.main[count.index].resource_group_name].id
# }

# # Configuring LB rules and probe for services

# resource "azurerm_lb_probe" "service" {
#   for_each = local.consul_services
#   loadbalancer_id = azurerm_lb.app[element([ for i in each.value : i.meta.resource_group ],0)].id
#   name            = each.key
#   port            = distinct(each.value[*].port)[0] # Assuming all instances of a service has the same port
# }

# resource "azurerm_lb_rule" "consul" {
#   # for_each = { for i,j in var.services : j.name => j.port ... }
#   # We create an object with maps to iterate to have services with ports and resource groups
#   # This is needed because LBs are based on the RG names and port comes from services
#   for_each = { for i,j in var.services : j.name => {port = j.port, rg = j.meta.resource_group} ... }
#   loadbalancer_id                = azurerm_lb.app[distinct(tolist(each.value))[0].rg].id
#   name                           = each.key
#   protocol                       = "Tcp"
#   # frontend_port                  = distinct(tolist(each.value))[0]
#   # backend_port                   = distinct(tolist(each.value))[0]
#   frontend_port                  = distinct(tolist(each.value))[0].port
#   backend_port                   = distinct(tolist(each.value))[0].port
#   frontend_ip_configuration_name = "consulconfiguration"
#   probe_id                       = azurerm_lb_probe.service[each.key].id
#   backend_address_pool_ids       = [azurerm_lb_backend_address_pool.app[distinct(tolist(each.value))[0].rg].id]
# }


