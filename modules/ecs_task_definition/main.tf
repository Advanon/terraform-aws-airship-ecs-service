locals {
  docker_volume_name = "${lookup(var.docker_volume, "name", "")}"
}

resource "aws_ecs_task_definition" "app" {
  count = "${(var.create && (local.docker_volume_name == "")) ? 1 : 0 }"

  family        = "${var.name}"
  task_role_arn = "${var.ecs_taskrole_arn}"

  # Execution role ARN can be needed inside FARGATE
  execution_role_arn = "${var.ecs_task_execution_role_arn}"

  # Used for Fargate
  cpu    = "${var.cpu}"
  memory = "${var.memory}"

  # This is a hack: https://github.com/hashicorp/terraform/issues/14037#issuecomment-361202716
  # Specifically, we are assigning a list of maps to the `volume` block to
  # mimic multiple `volume` statements
  # This WILL break in Terraform 0.12: https://github.com/hashicorp/terraform/issues/14037#issuecomment-361358928
  # but we need something that works before then
  volume = ["${var.host_path_volumes}"]

  container_definitions = "${var.container_definitions}"
  network_mode          = "${var.awsvpc_enabled ? "awsvpc" : "bridge"}"

  # We need to ignore future container_definitions, and placement_constraints, as other tools take care of updating the task definition
  lifecycle {
    ignore_changes = ["container_definitions", "placement_constraints"]
  }

  requires_compatibilities = ["${var.launch_type}"]
}

resource "aws_ecs_task_definition" "app_with_docker_volume" {
  count = "${(var.create && (local.docker_volume_name != "")) ? 1 : 0 }"

  family        = "${var.name}"
  task_role_arn = "${var.ecs_taskrole_arn}"

  # Execution role ARN can be needed inside FARGATE
  execution_role_arn = "${var.ecs_task_execution_role_arn}"

  # Used for Fargate
  cpu    = "${var.cpu}"
  memory = "${var.memory}"

  # This is a hack: https://github.com/hashicorp/terraform/issues/14037#issuecomment-361202716
  # Specifically, we are assigning a list of maps to the `volume` block to
  # mimic multiple `volume` statements
  # This WILL break in Terraform 0.12: https://github.com/hashicorp/terraform/issues/14037#issuecomment-361358928
  # but we need something that works before then
  volume = ["${var.host_path_volumes}"]

  # Unfortunately, the same hack doesn't work for a list of Docker volume
  # blocks because they include a nested map; therefore the only way to
  # currently sanely support Docker volume blocks is to only consider the
  # single volume case.
  volume = {
    name = "${local.docker_volume_name}"

    docker_volume_configuration {
      autoprovision = "${lookup(var.docker_volume, "autoprovision", false)}"
      scope         = "${lookup(var.docker_volume, "scope", "shared")}"
      driver        = "${lookup(var.docker_volume, "driver", "")}"
    }
  }

  container_definitions = "${var.container_definitions}"

  network_mode = "${var.awsvpc_enabled ? "awsvpc" : "bridge"}"

  # We need to ignore future container_definitions, and placement_constraints, as other tools take care of updating the task definition
  lifecycle {
    ignore_changes = ["container_definitions", "placement_constraints"]
  }

  requires_compatibilities = ["${var.launch_type}"]
}
