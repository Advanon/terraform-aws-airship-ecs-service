locals {
  ecs_cluster_name      = "${element(split("/",var.ecs_cluster_id),3)}"
  launch_type           = "${var.fargate_enabled ? "FARGATE" : "EC2" }"
  ssm_vars              = "${split(",", data.external.fetch-ssm-params.result["vars"])}"
  default_ssm_vars_path = "/${var.stage}/${var.name}/"

  ssm_vars_path = "${length(var.ssm_vars_path)== 0 ? local.default_ssm_vars_path : var.ssm_vars_path }"
}

#
# The iam sub-module creates the IAM resources needed for the ECS Service. 
#
module "iam" {
  source = "./modules/iam/"

  # Name
  name = "${local.ecs_cluster_name}-${var.name}"

  # Create defines if any resources need to be created inside the module
  create = "${var.create}"

  # Region ..
  region = "${var.region}"

  # kms_enabled sets whether this ecs_service should be able to access the given KMS keys.
  # Defaults to true; if no kms_paths are given, set this to false.
  kms_enabled = "${var.kms_enabled}"

  # kms_keys define which KMS keys this ecs_service can access.
  kms_keys = "${var.kms_keys}"

  # ssm_enabled sets whether this ecs_service should be able to access the given SSM paths.
  # Defaults to true; if no ssm_paths are given, set this to false.
  ssm_enabled = "${var.ssm_enabled}"

  # ssm_paths define which SSM paths the ecs_service can access
  ssm_paths = "${var.ssm_paths}"

  # s3_ro_paths define which paths on S3 can be accessed from the ecs service in read-only fashion.
  s3_ro_paths = "${var.s3_ro_paths}"

  # s3_rw_paths define which paths on S3 can be accessed from the ecs service in read-write fashion.
  s3_rw_paths = "${var.s3_rw_paths}"

  # In case Fargate is enabled an extra role needs to be added
  fargate_enabled = "${var.fargate_enabled}"

  container_image = "${var.container_image}"
}

#
# The alb-handling sub-module creates everything regarding the connection of an ecs service to an Application Load Balancer
# 
module "alb_handling" {
  source = "./modules/alb_handling/"

  name         = "${var.name}"
  cluster_name = "${local.ecs_cluster_name}"

  # Create defines if we need to create resources inside this module
  create = "${var.create && var.load_balancing_enabled}"

  # lb_vpc_id sets the VPC ID of where the LB resides
  lb_vpc_id = "${lookup(var.load_balancing_properties,"lb_vpc_id", "")}"

  # lb_arn defines the arn of the ALB
  lb_arn = "${lookup(var.load_balancing_properties,"lb_arn", "")}"

  # lb_listener_arn is the arn of the listener ( HTTP )
  lb_listener_arn = "${lookup(var.load_balancing_properties,"lb_listener_arn", "")}"

  # lb_listener_arn_https is the arn of the listener ( HTTPS )
  lb_listener_arn_https = "${lookup(var.load_balancing_properties,"lb_listener_arn_https", "")}"

  # unhealthy_threshold defines the threashold for the target_group after which a service is seen as unhealthy.
  unhealthy_threshold = "${lookup(var.load_balancing_properties,"unhealthy_threshold", var.default_load_balancing_properties_unhealthy_threshold)}"

  # if https_enabled is true, listener rules are made for the ssl listener
  https_enabled = "${lookup(var.load_balancing_properties,"https_enabled", var.default_load_balancing_properties_https_enabled)}"

  # Sets the deregistration_delay for the targetgroup
  deregistration_delay = "${lookup(var.load_balancing_properties,"deregistration_delay", var.default_load_balancing_properties_deregistration_delay)}"

  # route53_record_type sets the record type of the route53 record, can be ALIAS, CNAME or NONE,  defaults to CNAME
  # In case of NONE no record will be made
  route53_record_type = "${lookup(var.load_balancing_properties,"route53_record_type", var.default_load_balancing_properties_route53_record_type)}"

  # Sets the zone in which the sub-domain will be added for this service
  route53_zone_id = "${lookup(var.load_balancing_properties,"route53_zone_id", "")}"

  # Sets name for the sub-domain, we default to *name
  route53_name = "${var.name}"

  # route53_a_record_identifier sets the identifier of the weighted Alias A record
  route53_record_identifier = "${lookup(var.load_balancing_properties,"route53_record_identifier", var.default_load_balancing_properties_route53_record_identifier)}"

  # custom_listen_hosts will be added as a host route rule as aws_lb_listener_rule to the given service e.g. www.domain.com -> Service
  custom_listen_hosts = "${var.custom_listen_hosts}"

  # health_uri defines which health-check uri the target group needs to check on for health_check
  health_uri = "${lookup(var.load_balancing_properties,"health_uri", var.default_load_balancing_properties_health_uri)}"

  # target_type is the alb_target_group target, in case of EC2 it's instance, in case of FARGATE it's IP
  target_type = "${var.awsvpc_enabled ? "ip" : "instance"}"
}

###### CloudWatch Logs
resource "aws_cloudwatch_log_group" "app" {
  count             = "${var.create ? 1 : 0}"
  name              = "${local.ecs_cluster_name}/${var.name}"
  retention_in_days = 14
}

#
# Container_definition
#
module "ecs-container-definition" {
  source                       = "cloudposse/ecs-container-definition/aws"
  version                      = "0.14.0"
  container_name               = "${var.container_name}"
  container_image              = "${var.container_image}"
  container_cpu                = "${var.container_cpu}"
  container_memory             = "${var.container_memory}"
  container_memory_reservation = "${var.container_memory_reservation}"
  entrypoint                   = "${var.container_entrypoint}"
  healthcheck                  = "${var.container_healthcheck}"
  command                      = "${var.container_command}"

  port_mappings = [
    {
      containerPort = "${var.container_port}"
      hostPort      = "${var.awsvpc_enabled ? var.container_port : var.host_port }"
      protocol      = "tcp"
    },
  ]

  environment  = "${var.container_envvars}"
  secrets      = "${null_resource.convert-to-container-vars.*.triggers}"
  mount_points = ["${var.mountpoints}"]

  log_options = {
    "awslogs-region"        = "${var.region}"
    "awslogs-group"         = "${element(concat(aws_cloudwatch_log_group.app.*.name, list("")), 0)}"
    "awslogs-stream-prefix" = "${var.name}"
  }
}

#
# The ecs_task_definition sub-module creates the ECS Task definition
# 
module "ecs_task_definition" {
  source = "./modules/ecs_task_definition/"

  create = "${var.create}"

  # The name of the task_definition (generally, a combination of the cluster name and the service name)
  name = "${local.ecs_cluster_name}-${var.name}"

  cluster_name = "${local.ecs_cluster_name}"

  container_definitions = "${module.ecs-container-definition.json}"

  # awsvpc_enabled sets if the ecs task definition is awsvpc 
  awsvpc_enabled = "${var.awsvpc_enabled}"

  # fargate_enabled sets if the ecs task definition has launch_type FARGATE
  fargate_enabled = "${var.fargate_enabled}"

  # Sets the task cpu needed for fargate when enabled
  cpu = "${var.fargate_enabled ? var.container_cpu : "" }"

  # Sets the task memory which is mandatory for Fargate, option for EC2
  memory = "${var.fargate_enabled ? var.container_memory : "" }"

  # ecs_taskrole_arn sets the IAM role of the task.
  ecs_taskrole_arn = "${module.iam.ecs_taskrole_arn}"

  # ecs_task_execution_role_arn sets the task-execution role needed for FARGATE. This role is also empty in case of EC2
  ecs_task_execution_role_arn = "${module.iam.ecs_task_execution_role_arn}"

  # Launch type, either EC2 or FARGATE
  launch_type = "${local.launch_type}"

  # region, needed for Logging.. 
  region = "${var.region}"

  # a Docker volume to add to the task
  docker_volume = "${var.docker_volume}"

  # list of host paths to add as volumes to the task
  host_path_volumes = "${var.host_path_volumes}"
}

#
# The ecs_service sub-module creates the ECS Service
# 
module "ecs_service" {
  source = "./modules/ecs_service/"

  name = "${var.name}"

  # create defines if resources are being created inside this module
  create = "${var.create}"

  cluster_id = "${var.ecs_cluster_id}"

  # ecs_task_definition_arn is the arn of the task definition, created by the ecs_task_definition module 
  ecs_task_definition_arn = "${module.ecs_task_definition.aws_ecs_task_definition_arn}"

  # launch_type either EC2 or FARGATE
  launch_type = "${local.launch_type}"

  # deployment_maximum_percent sets the maximum size of the deployment in % of the normal size.
  deployment_maximum_percent = "${lookup(var.capacity_properties,"deployment_maximum_percent", var.default_capacity_properties_deployment_maximum_percent)}"

  # deployment_minimum_healthy_percent sets the minimum % in capacity at depployment
  deployment_minimum_healthy_percent = "${lookup(var.capacity_properties,"deployment_minimum_healthy_percent", var.default_capacity_properties_deployment_minimum_healthy_percent)}"

  lb_attached = "${length(lookup(var.load_balancing_properties,"lb_arn", "")) > 0 ? true : false}"

  # awsvpc_subnets defines the subnets for an awsvpc ecs module
  awsvpc_subnets = "${var.awsvpc_subnets}"

  # awsvpc_security_group_ids defines the vpc_security_group_ids for an awsvpc module
  awsvpc_security_group_ids = "${concat(list(aws_security_group.ecs_service_sg.id), var.awsvpc_security_group_ids)}"

  # lb_target_group_arn sets the arn of the target_group the service needs to connect to
  lb_target_group_arn = "${module.alb_handling.lb_target_group_arn}"

  # desired_capacity sets the initial capacity in task of the ECS Service, ignored when scheduling_strategy is DAEMON
  desired_capacity = "${lookup(var.capacity_properties,"desired_capacity", var.default_capacity_properties_desired_capacity)}"

  # scheduling_strategy
  scheduling_strategy = "${var.scheduling_strategy}"

  # with_placement_strategy, if true spread tasks over ECS Cluster based on AZ, Instance-id, Memory
  with_placement_strategy = "${var.with_placement_strategy}"

  # container_name sets the name of the container, this is used for the load balancer section inside the ecs_service to connect to a container_name defined inside the 
  # task definition, container_port sets the port for the same container.
  container_name = "${var.container_name}"

  container_port = "${var.container_port}"

  # This way we force the aws_lb_listener_rule to have finished before creating the ecs_service
  aws_lb_listener_rules = "${module.alb_handling.aws_lb_listener_rules}"
}

#
# This modules sets the scaling properties of the ECS Service
#
module "ecs_autoscaling" {
  source = "./modules/ecs_autoscaling/"

  # create defines if resources inside this module are being created.
  create = "${var.create && length(var.scaling_properties) > 0 ? true : false }"

  cluster_name = "${local.ecs_cluster_name}"

  # ecs_service_name is derived from the actual ecs_service, this to force dependency at creation.
  ecs_service_name = "${module.ecs_service.ecs_service_name}"

  # desired_min_capacity, in case of autoscaling, desired_min_capacity sets the minimum size in tasks
  desired_min_capacity = "${lookup(var.capacity_properties,"desired_min_capacity", var.default_capacity_properties_desired_min_capacity)}"

  # desired_max_capaity, in case of autoscaling, desired_max_capacity sets the maximum size in tasks
  desired_max_capacity = "${lookup(var.capacity_properties,"desired_max_capacity", var.default_capacity_properties_desired_max_capacity)}"

  # scaling_properties holds a list of maps with the scaling properties defined.
  scaling_properties = "${var.scaling_properties}"
}

resource "aws_security_group" "ecs_service_sg" {
  vpc_id      = "${data.aws_vpc.this.id}"
  description = "${var.name} ECS service tasks security group"
  name        = "${var.name}-ecs-service"

  ingress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = ["${data.aws_vpc.this.cidr_block}"]
  }

  egress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "null_resource" "convert-to-container-vars" {
  count = "${length(local.ssm_vars)}"

  triggers = {
    "name"      = "${element(local.ssm_vars, count.index)}"
    "valueFrom" = "${local.ssm_vars_path}${element(local.ssm_vars, count.index)}"
  }
}

data "external" "fetch-ssm-params" {
  program = ["bash", "${path.module}/scripts/get-ssm-param-names.sh"]

  query {
    region   = "${var.region}"
    ssm_path = "${local.ssm_vars_path}"
  }
}

data "aws_vpc" "this" {
  filter {
    name   = "tag:Name"
    values = ["${var.vpc_name}"]
  }
}
