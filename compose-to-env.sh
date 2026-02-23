#!/bin/bash

# --- FONCTION D'INSTALLATION DES PRÉREQUIS ---
check_requirements() {
    local missing_deps=()
    
    if ! command -v yq &> /dev/null; then missing_deps+=("yq"); fi
    if ! command -v curl &> /dev/null; then missing_deps+=("curl"); fi

    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo "⚠️  Dépendances manquantes : ${missing_deps[*]}"
        read -p "Voulez-vous les installer automatiquement ? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Installation en cours..."
            # Installation de curl si nécessaire
            if [[ " ${missing_deps[*]} " =~ " curl " ]]; then
                sudo apt-get update && sudo apt-get install -y curl
            fi
            # Installation de yq (détection automatique de l'architecture)
            if [[ " ${missing_deps[*]} " =~ " yq " ]]; then
                case "$(uname -m)" in
                    x86_64)  YQ_ARCH="amd64" ;;
                    aarch64) YQ_ARCH="arm64" ;;
                    armv7l)  YQ_ARCH="arm"   ;;
                    armv6l)  YQ_ARCH="arm"   ;;
                    *)       echo "❌ Architecture $(uname -m) non supportée pour yq."; exit 1 ;;
                esac
                sudo curl -L "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${YQ_ARCH}" -o /usr/bin/yq
                sudo chmod +x /usr/bin/yq
            fi
            echo "✅ Installation terminée."
        else
            echo "❌ Abandon. Le script a besoin de 'yq' pour fonctionner sans corrompre vos fichiers YAML."
            exit 1
        fi
    fi
}

# --- DÉBUT DU SCRIPT ---

# 1. Vérification et Installation
check_requirements

# 2. Recherche récursive des fichiers docker-compose
echo "🔍 Recherche des fichiers docker-compose..."

find . -type f \( -name "docker-compose.yaml" -o -name "docker-compose.yml" \) 2>/dev/null | while read -r compose_file; do
    dir=$(dirname "$compose_file")
    echo "---"
    echo "📂 Traitement de : $compose_file"

    # Récupérer la liste des services qui ont une section 'environment'
    services=$(yq e '.services | with_entries(select(.value.environment)) | keys | .[]' "$compose_file")

    if [ -z "$services" ]; then
        echo "  -> Aucun service avec 'environment' à migrer."
        continue
    fi

    for service in $services; do
        env_file_name="$service.env"
        full_env_path="$dir/$env_file_name"
        
        echo "  ⚡ Migration du service : $service"

        # Extraction des variables d'env vers le fichier .env
        # yq extrait le contenu de 'environment', sed nettoie les tirets si c'est une liste
        # Note : on utilise la notation ["..."] pour éviter que yq interprète les points dans les noms de services
        yq e ".services[\"$service\"].environment" "$compose_file" | sed 's/^- //g' > "$full_env_path"

        # Modification du YAML : Supprime 'environment' et ajoute 'env_file'
        yq e -i "del(.services[\"$service\"].environment)" "$compose_file"
        yq e -i ".services[\"$service\"].env_file = [\"$env_file_name\"]" "$compose_file"
        
        echo "     ✅ Créé : $env_file_name et mis à jour docker-compose.yaml"
    done
done

echo "---"
echo "🎉 Opération terminée avec succès."
