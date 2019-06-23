# AWS ECS Service Terraform Module  
This module is a _double-fork_ based on https://github.com/blinkist/terraform-aws-airship-ecs-cluster and https://github.com/Advanon/terraform-aws-airship-ecs-cluster

Also consider checking the [old README](README_old.md).


## Differences from the fork
Main changes made to the module since its forking:  
1) the container definition internal (sub-)module has been replaced with `cloudposse/ecs-container-definition/aws` - additional input vars have been added.
2) an `external` data source/provider is being used with a script to fetch all SSM parameters matching a path and pass them via a `null_resource` as secrets to the container definition
3) The Task Execution Role is now used by both EC2 and Fargate `launch_type`. The execution role incl. ECR permissions
4) Non-secret(SSM-based) environment variables can be passed as a list of maps to `container_envvars`
5) ECS service tasks have their own security group which allows all VPC traffic ingress, and egress to `0.0.0.0/0`, `concat` with a list provided as `awsvpc_security_group_ids`
6) Adds a `aws_vpc` data source based on the name provided as a (mandatory) input

## Versioning  
`1.x.x` - will include all the changes mentioned above to the original fork  
`0.5.x` - retains the versioning and changes of the original fork(s)  

## Examples  
- [ ] TODO  

## Inputs/Outputs  
- [ ] TODO