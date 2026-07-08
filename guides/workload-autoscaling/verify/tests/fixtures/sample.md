# Sample

<!-- local:step id=first -->
```bash
echo first-command
```

Some prose.

<!-- local:step id=second -->
```bash
kubectl apply -f second.yaml
```

<!-- local:step id=informational ignore="just output" -->
```bash
kubectl get pods
```

<!-- local:step id=amanifest file="thing.yaml" -->
```yaml
kind: Thing
name: demo
```
