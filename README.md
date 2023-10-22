# az-vnetlab

Hub and Spoke vnet with Bastion, a VM in each subnet for debugging 
and a spoke with an app service engine (public, managed ssl) which
talks to a blob storage over the vnet, secured by nsgs and service config.

All internal traffic, including AZ PAAS Services is securely routed within the VNET.