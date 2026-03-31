## AWS Platform Overview

This stack demonstrates how to provision an EKS cluster, deploy Argo CD via Terraform/Helm, and wire it up to external services such as AWS Secrets Manager. The goal is to showcase a production-friendly setup where Argo CD runs behind the AWS Load Balancer Controller with a webapp, api, websocket server and worker pods.

## Prereqs

Create kubeconfig so we can connect to EKS with kubectl
```bash
aws eks update-kubeconfig --region <region> --name <cluster-name>

aws eks update-kubeconfig \
  --name test-eks-cluster \
  --region us-east-1 \
  --role-arn arn:aws:iam::<aws-account-id>:role/<your-assumed-iam-role>
```


Grab ingress url of argocd once its running:
```bash
kubectl get ingress -n argocd argo-cd-argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

You can visit the URL and login by grabbing the secret value from AWS Secrets Manager

## Debug ArgoCD + ExternalRedis

- Debugging external Redis for Argo CD:
  - `kubectl -n argocd exec argo-cd-argocd-application-controller-0 -c application-controller -- env | grep REDIS` to confirm the pod is wired to the right ElastiCache host, username, and password.
  

  - Check and make sure the `argocd-application-controller` pod doesn't have errors.`kubectl -n argocd logs argo-cd-argocd-application-controller-0 -c application-controller | grep -i redis` if there isn't any `i/o timeout` or `server timeout` messages, the controller is successfully talking to Redis.

  - Launch a one-off pod to test the network path: `kubectl run redis-debug -n argocd --restart=Never --rm -it --image=redis:7 --command -- sh` and inside run `redis-cli -h <elasticache-endpoint> -p 6379 ping` (add `--tls` and `-a $REDIS_PASSWORD` if TLS/auth is enabled). A `PONG` confirms the cluster can reach ElastiCache.
  - If TLS is required, set the Argo CD Helm values to use tls for redis.

  ```json
    controller = {
        extraArgs = [
        "--redis-use-tls",
        ]
    }

    repoServer = {
        extraArgs = [
        "--redis-use-tls",
        ]
    }


    server = {
        extraArgs = [
        "--redis-use-tls",
        ]
    }
	...