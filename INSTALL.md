# 📦 Guia de Instalação do xPanel com Traefik

Este guia detalha o processo completo de instalação do **xPanel** com **Traefik como proxy reverso** e **SSL automático**.

> ✅ Instalação automática em 2 minutos  
> 🔐 Segurança por padrão  
> 🌐 Suporte a IP ou domínio  
> 🔄 Escalável para múltiplos serviços

---

## 🧰 Pré-requisitos

Antes de instalar, certifique-se de que sua VPS atende aos requisitos:

- **Sistema Operacional**: Ubuntu 20.04, 22.04 ou 24.04
- **Memória RAM**: Mínimo 2GB (recomendado)
- **Espaço em disco**: 20GB+
- **Acesso root**: Você deve ter permissão `sudo`
- **Domínio (opcional)**: Para SSL com Let's Encrypt

---

## 🚀 Instalação Automática (recomendado)

Execute o comando abaixo em uma VPS limpa:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/SxConnect/xpanel-installer/main/utils/install.sh)
