resource "aws_iam_role" "lambda_scaler_role" {
  name = "taskflow-vertical-scaler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_policy" "lambda_ecs_policy" {
  name = "taskflow-vertical-scaler-ecs-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["ecs:DescribeServices", "ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition", "ecs:UpdateService"]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action   = ["iam:PassRole"]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_ecs" {
  role       = aws_iam_role.lambda_scaler_role.name
  policy_arn = aws_iam_policy.lambda_ecs_policy.arn
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/scaler.zip"

  source {
    content  = <<-EOF
import boto3

ecs = boto3.client('ecs')

def lambda_handler(event, context):
    cluster = "${var.ecs_cluster_name}"
    service = "${var.ecs_service_name}"

    services = ecs.describe_services(cluster=cluster, services=[service])
    task_def_arn = services['services'][0]['taskDefinition']
    task_def = ecs.describe_task_definition(taskDefinition=task_def_arn)['taskDefinition']

    # Scale memory vertically from 512 -> 1024 or 256 -> 512 CPU
    new_cpu = "512"
    new_memory = "1024"

    response = ecs.register_task_definition(
        family=task_def['family'],
        taskRoleArn=task_def.get('taskRoleArn', ''),
        executionRoleArn=task_def.get('executionRoleArn', ''),
        networkMode=task_def['networkMode'],
        containerDefinitions=task_def['containerDefinitions'],
        requiresCompatibilities=task_def['requiresCompatibilities'],
        cpu=new_cpu,
        memory=new_memory
    )

    new_task_def_arn = response['taskDefinition']['taskDefinitionArn']
    ecs.update_service(
        cluster=cluster,
        service=service,
        taskDefinition=new_task_def_arn,
        forceNewDeployment=True
    )
    return {"status": "Vertical scale complete", "new_task_def": new_task_def_arn}
EOF
    filename = "index.py"
  }
}

resource "aws_lambda_function" "scaler" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "taskflow-vertical-scaler"
  role             = aws_iam_role.lambda_scaler_role.arn
  handler          = "index.lambda_handler"
  runtime          = "python3.11"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "taskflow-ecs-high-cpu"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  alarm_actions       = [aws_lambda_function.scaler.arn]

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scaler.function_name
  principal     = "lambda.alarms.cloudwatch.amazonaws.com"
  source_arn    = aws_cloudwatch_metric_alarm.high_cpu.arn
}
