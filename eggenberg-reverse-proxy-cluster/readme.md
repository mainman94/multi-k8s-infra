# Alpine Linux Setup

> **Kurzanleitung für die grundlegende Alpine Linux-Konfiguration**

---

## Voraussetzungen

- Alpine Linux installiert
- Root-Zugriff

---

## 1. Installiere `curl`

```sh
apk add curl
```

---

## 2. Konfiguriere `tmpfs` für `/run`

Füge folgende Zeile zu `/etc/fstab` hinzu:

```sh
echo 'tmpfs /run tmpfs rw,nosuid,nodev,noexec,relatime,size=10%,mode=755,shared 0 0' | tee -a /etc/fstab
```

---

## 3. Bearbeite die `fstab`

Öffne `/etc/fstab` und prüfe die Einträge:

```
/dev/vg0/lv_root  /  ext4  rw,relatime,shared  0 1
# /dev/vg0/lv_root      /       ext4    rw,relatime 0 1
```

---

> ℹ️ Weitere Informationen findest du in der [offiziellen Alpine Linux Dokumentation](https://docs.alpinelinux.org/).