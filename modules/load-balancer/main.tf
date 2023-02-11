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
  group_ports = { for rg,ports in {for a,b in var.services : b.meta.resource_group => b.port...} : rg => distinct(ports) }
  services_unique_ports = { for service,data in local.consul_services : service => distinct(data[*].port)[0] }
  # Map of vm ==> rg
  vms = distinct([ for i in var.services : { vms = i.meta.azure_vm, rgs = i.meta.resource_group} ])

 
}

resource "azurerm_public_ip" "lb" {
  name                = var.lb_name
  location            = var.location
  resource_group_name = var.resource_group
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label = "demoapp-${var.lb_name}"
}

resource "azurerm_lb" "app" {
  name                = "lb-${var.lb_name}"
  location            = var.location
  resource_group_name = var.resource_group

  sku = "Standard"

  frontend_ip_configuration {
    name                 = "consulconfiguration"
    public_ip_address_id = azurerm_public_ip.lb.id
  }
}

resource "azurerm_lb_backend_address_pool" "app" {
  loadbalancer_id = azurerm_lb.app.id
  name            = "demoapp-${var.lb_name}"
}

resource "azurerm_network_interface_backend_address_pool_association" "app" {
  count = length(var.network_interfaces)
  network_interface_id    = var.network_interfaces[count.index]
  ip_configuration_name   = "consulconfiguration"
  backend_address_pool_id = azurerm_lb_backend_address_pool.app.id
}

# Configuring LB rules and probe for services

resource "azurerm_lb_probe" "service" {
  for_each = local.consul_services
  loadbalancer_id = azurerm_lb.app.id
  name            = each.key
  port            = distinct(each.value[*].port)[0] # Assuming all instances of a service has the same port
}

resource "azurerm_lb_rule" "consul" {
  # for_each = { for i,j in var.services : j.name => j.port ... }
  # We create an object with maps to iterate to have services with ports and resource groups
  # This is needed because LBs are based on the RG names and port comes from services
  for_each = { for i,j in var.services : j.name => {port = j.port, rg = j.meta.resource_group} ... }
  loadbalancer_id                = azurerm_lb.app.id
  name                           = each.key
  protocol                       = "Tcp"
  # frontend_port                  = distinct(tolist(each.value))[0]
  # backend_port                   = distinct(tolist(each.value))[0]
  frontend_port                  = distinct(tolist(each.value))[0].port
  backend_port                   = distinct(tolist(each.value))[0].port
  frontend_ip_configuration_name = "consulconfiguration"
  probe_id                       = azurerm_lb_probe.service[each.key].id
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.app.id]
}