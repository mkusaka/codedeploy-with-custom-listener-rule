# codedeploy-with-custom-listener-rule

memo

## command
* aws deploy create-deployment --application-name axum-app --deployment-config-name CodeDeployDefault.ECSAllAtOnce --deployment-group-name axum-group --description "Deploy Axum app" --revision '{"revisionType":"AppSpecContent","appSpecContent":{"content":"{\"version\": \"0.0\",\"Resources\":[{\"TargetService\":{\"Type\":\"AWS::ECS::Service\",\"Properties\":{\"TaskDefinition\":\"arn:aws:ecs:ap-northeast-1:310808741199:task-definition/axum-task:4\",\"LoadBalancerInfo\":{\"ContainerName\":\"axum-app\",\"ContainerPort\":80}}}}]}"}}'