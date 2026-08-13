## LAMBDA LAYER
# Ships lambdas/common/ as a shared layer so each handler zip stays small,
# matching the xomify-shared-packages / xomtracks pattern. Real content is
# deployed by CI (deploy-backend.yml); the stub here only satisfies Terraform's
# required filename/hash on first apply.

resource "aws_lambda_layer_version" "lambda_layer" {
  description = "Currently managed by ${var.app_name}"
  layer_name  = "${var.app_name}-shared-packages"

  filename            = "./templates/lambda_stub.zip"
  source_code_hash    = filebase64sha256("./templates/lambda_stub.zip")
  compatible_runtimes = [var.lambda_runtime]

  lifecycle {
    ignore_changes = [
      description,
      filename,
      source_code_hash
    ]
  }
}
