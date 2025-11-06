# ArgoCD Installation Guide

Dieses Dokument beschreibt die Schritte zur Installation von ArgoCD in einem Kubernetes-Cluster.

---

## Voraussetzungen
- Ein funktionierendes Kubernetes-Cluster.
- `kubectl` und `helm` sind installiert und konfiguriert.
- Ein DNS-Eintrag für `argo-ha.philippmhauptmann.me`, der auf den Ingress-Controller zeigt.

---

## Installation

### 1. Namespace anlegen
Erstelle den Namespace `argocd`, falls er noch nicht existiert:
```bash
kubectl create namespace argocd
```

### 2. Helm-Repo hinzufügen
Füge das ArgoCD-Helm-Repository hinzu und aktualisiere es:
```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
```

### 3. Installation mit eigenen Werten
Installiere ArgoCD mit einer benutzerdefinierten `values.yaml`-Datei:
```bash
helm install argocd oci://ghcr.io/argoproj/argo-helm/argo-cd \
  --namespace argocd \
  --version 9.0.5 \
  -f values.yaml
```

---

## Konfiguration

### 1. Zugriff auf das ArgoCD-Dashboard
Nach der Installation ist das ArgoCD-Dashboard unter `https://argo-ha.philippmhauptmann.me` verfügbar. Stelle sicher, dass der DNS-Eintrag korrekt ist.

### 2. Standard-Anmeldedaten
- **Benutzername:** `admin`
- **Passwort:** Das Passwort kann mit folgendem Befehl abgerufen werden:
  ```bash
  kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode
  ```

### 3. TLS-Zertifikat
Das TLS-Zertifikat wird automatisch mit Cert-Manager und Let's Encrypt generiert. Stelle sicher, dass Cert-Manager im Cluster installiert ist und der Cluster-Issuer `letsencrypt-cloudflare` konfiguriert ist.

---

## Skalierung und Monitoring

### Autoscaling
ArgoCD ist so konfiguriert, dass es automatisch skaliert:
- **Server:** Mindestens 2 Replikate.
- **Controller:** Mindestens 1 Replikat.
- **RepoServer:** Mindestens 2 Replikate.

### Metriken
Metriken für Server, Controller, RepoServer und Redis-HA sind aktiviert und können in Prometheus überwacht werden.

---

## Fehlerbehebung

### 1. ArgoCD-Pods prüfen
Falls Probleme auftreten, überprüfe die Pods im Namespace `argocd`:
```bash
kubectl get pods -n argocd
```

### 2. Logs abrufen
Abrufen der Logs eines spezifischen Pods:
```bash
kubectl logs -n argocd <pod-name>
```

### 3. Ingress prüfen
Falls das Dashboard nicht erreichbar ist, überprüfe den Ingress:
```bash
kubectl get ingress -n argocd
```

---

## Ressourcen
- [Offizielle ArgoCD-Dokumentation](https://argo-cd.readthedocs.io/)
- [ArgoCD Helm Chart](https://github.com/argoproj/argo-helm)