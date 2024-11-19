#!/bin/sh
#####################################################################################################
#
# ABOUT THIS PROGRAM
#
# NAME
#	ThunderbirdInstall.sh -- Installs or updates Thunderbird with user approval via swiftDialog
#
# SYNOPSIS
#	sudo ThunderbirdInstall.sh
#
####################################################################################################
#
# HISTORY
#
#	Version: 1.4
#
#	  - DJELAL Oussama, 2024-11-06
#   - Correction de l'extraction de l'URL de téléchargement
#   - Ajout de gestion des erreurs améliorée
#   - Ajout de la confirmation de mise à jour via swiftDialog
#
####################################################################################################
# Script to download and install Thunderbird.
# Now supports Intel and ARM systems.
# User confirmation required via swiftDialog before proceeding with update.
#
# Choose language (en-US, fr, de, etc.)
lang="fr"  # Langue par défaut définie en français

echo "Démarrage du script d'installation/mise à jour de Thunderbird..."

# VÉRIFICATION SI UNE VALEUR A ÉTÉ PASSÉE EN PARAMÈTRE 4 ET, LE CAS ÉCHÉANT, ASSIGNER À "lang"
if [ -n "$4" ]; then  # Vérifie si $4 n'est pas vide
    lang="$4"
    echo "Paramètre de langue détecté, définition de la langue sur $lang"
else
    echo "Aucun paramètre de langue fourni. Utilisation de la langue par défaut : $lang"
fi

dmgfile="TB.dmg"
logfile="/Library/Logs/ThunderbirdInstallScript.log"

echo "Fichier de log : $logfile"
echo "Vérification de l'architecture du système..."

# Vérifie si nous sommes sur Intel ou ARM en utilisant uname -m
arch=$(/usr/bin/uname -m)
echo "Architecture détectée : $arch"

if [ "$arch" = "i386" ] || [ "$arch" = "x86_64" ] || [ "$arch" = "arm64" ]; then
    echo "Architecture prise en charge : $arch"

    ## Obtenir la version du système d'exploitation et ajuster pour l'utilisation dans l'URL
    OSvers=$(sw_vers -productVersion)
    OSvers_URL=$(echo "$OSvers" | sed 's/[.]/_/g')
    echo "Version du système d'exploitation : $OSvers (format URL : $OSvers_URL)"

    ## Définir la chaîne User Agent pour utiliser avec curl
    userAgent="Mozilla/5.0 (Macintosh; ${arch} Mac OS X ${OSvers_URL}) AppleWebKit/535.6.2 (KHTML, like Gecko) Version/5.2 Safari/535.6.2"
    echo "User Agent défini pour curl : $userAgent"

    # Obtenir la dernière version de Thunderbird disponible depuis la page de Thunderbird
    echo "Récupération des informations de la dernière version de Thunderbird..."

    # Utiliser curl pour suivre les redirections et obtenir l'URL finale du DMG
    download_url=$(curl -s -L -A "$userAgent" -o /dev/null -w '%{url_effective}' "https://download.mozilla.org/?product=thunderbird-latest&os=osx&lang=${lang}")

    if [ -z "$download_url" ]; then
        echo "Erreur : Impossible de récupérer l'URL de téléchargement de Thunderbird."
        echo "$(date): ERREUR : Impossible de récupérer l'URL de téléchargement de Thunderbird." >> "${logfile}"
        exit 1
    fi

    echo "URL de téléchargement obtenue : $download_url"

    # Extraire la version de l'URL
    latestver=$(basename "$download_url" | sed -E 's/^Thunderbird%20([0-9]+\.[0-9]+\.[0-9]+)\.dmg$/\1/')

    if [ -z "$latestver" ]; then
        echo "Erreur : Impossible d'extraire la version de Thunderbird à partir de l'URL."
        echo "$(date): ERREUR : Impossible d'extraire la version de Thunderbird à partir de l'URL." >> "${logfile}"
        exit 1
    fi

    echo "Dernière version disponible de Thunderbird : $latestver"

    # Obtenir le numéro de version de Thunderbird actuellement installé, le cas échéant
    if [ -e "/Applications/Thunderbird.app" ]; then
        currentinstalledver=$(/usr/bin/defaults read /Applications/Thunderbird.app/Contents/Info CFBundleShortVersionString 2>/dev/null)
        if [ $? -ne 0 ] || [ -z "$currentinstalledver" ]; then
            currentinstalledver="none"
            echo "Thunderbird n'est pas correctement installé ou la version ne peut être déterminée."
            echo "$(date): Thunderbird n'est pas correctement installé ou la version ne peut être déterminée." >> "${logfile}"
        else
            echo "Version actuellement installée de Thunderbird : $currentinstalledver"
        fi
    else
        currentinstalledver="none"
        echo "Thunderbird n'est pas actuellement installé."
        echo "$(date): Thunderbird n'est pas actuellement installé." >> "${logfile}"
    fi

    # Demande de confirmation à l'utilisateur avant de continuer
    /usr/local/bin/dialog --title "Mise à jour de Thunderbird" --message "Une nouvelle version de Thunderbird est disponible. Souhaitez-vous mettre à jour maintenant ?

Attention : ceci redémarrera votre messagerie" --icon "/usr/local/share/brandingimage.png" --button1text "Mettre à jour" --button2text "Annuler"
    user_choice=$?

    if [ "$user_choice" -ne 0 ]; then
        echo "Mise à jour annulée par l'utilisateur. Fin du script."
        echo "$(date): Mise à jour annulée par l'utilisateur." >> ${logfile}
        exit 0
    fi

    url="$download_url"
    
    echo "URL de téléchargement de la dernière version : $url"
    echo "$(date): URL de téléchargement : $url" >> "${logfile}"

    # Comparer les deux versions. Si elles sont différentes ou si Thunderbird n'est pas présent, télécharger et installer la nouvelle version.
    if [ "${currentinstalledver}" != "${latestver}" ]; then
        echo "Une nouvelle version de Thunderbird est disponible. Téléchargement et installation en cours..."
        echo "$(date): Version actuelle de Thunderbird : ${currentinstalledver}" >> "${logfile}"
        echo "$(date): Version disponible de Thunderbird : ${latestver}" >> "${logfile}"
        echo "$(date): Téléchargement de la nouvelle version..." >> "${logfile}"
        
        /usr/bin/curl -s -L -A "$userAgent" -o /tmp/"${dmgfile}" "${url}"
        
        if [ $? -ne 0 ]; then
            echo "Erreur : Échec du téléchargement de Thunderbird."
            echo "$(date): ERREUR : Échec du téléchargement de Thunderbird." >> "${logfile}"
            exit 1
        fi
        
        echo "Téléchargement terminé. Montage de l'image disque..."
        echo "$(date): Montage de l'image disque d'installation." >> "${logfile}"
        
        /usr/bin/hdiutil attach /tmp/"${dmgfile}" -nobrowse -quiet
        if [ $? -ne 0 ]; then
            echo "Erreur : Échec du montage de l'image disque."
            echo "$(date): ERREUR : Échec du montage de l'image disque." >> "${logfile}"
            /bin/rm /tmp/"${dmgfile}"
            exit 1
        fi
        
        echo "Installation de Thunderbird..."
        echo "$(date): Installation de Thunderbird..." >> "${logfile}"
        echo "Copie de Thunderbird dans le dossier Applications..."
        
        ditto -rsrc "/Volumes/Thunderbird/Thunderbird.app" "/Applications/Thunderbird.app"
        if [ $? -ne 0 ]; then
            echo "Erreur : Échec de la copie de Thunderbird dans Applications."
            echo "$(date): ERREUR : Échec de la copie de Thunderbird dans Applications." >> "${logfile}"
            /usr/bin/hdiutil detach "/Volumes/Thunderbird" -quiet
            /bin/rm /tmp/"${dmgfile}"
            exit 1
        fi
        
        /bin/sleep 10
        echo "Démontage de l'image disque..."
        echo "$(date): Démontage de l'image disque d'installation." >> "${logfile}"
        /usr/bin/hdiutil detach "/Volumes/Thunderbird" -quiet
        if [ $? -ne 0 ]; then
            echo "Erreur : Échec du démontage de l'image disque."
            echo "$(date): ERREUR : Échec du démontage de l'image disque." >> "${logfile}"
            /bin/rm /tmp/"${dmgfile}"
            exit 1
        fi
        
        /bin/sleep 10
        echo "Suppression du fichier d'image disque temporaire..."
        echo "$(date): Suppression de l'image disque." >> "${logfile}"
        /bin/rm /tmp/"${dmgfile}"
        
        # Vérifier si la nouvelle version a été installée
        newlyinstalledver=$(/usr/bin/defaults read /Applications/Thunderbird.app/Contents/Info CFBundleShortVersionString 2>/dev/null)
        if [ "${latestver}" = "${newlyinstalledver}" ]; then
            echo "SUCCESS : Thunderbird a été mis à jour à la version ${newlyinstalledver}"
            echo "$(date): SUCCESS: Thunderbird a été mis à jour à la version ${newlyinstalledver}" >> "${logfile}"
        else
            echo "ERREUR : Mise à jour de Thunderbird échouée, la version reste à ${currentinstalledver}."
            echo "$(date): ERREUR: Mise à jour de Thunderbird échouée, la version reste à ${currentinstalledver}." >> "${logfile}"
            echo "--" >> "${logfile}"
            exit 1
        fi
    
    # Si Thunderbird est déjà à jour, enregistrer et quitter.
    else
        echo "Thunderbird est déjà à jour, version actuelle : ${currentinstalledver}."
        echo "$(date): Thunderbird est déjà à jour, version actuelle : ${currentinstalledver}." >> "${logfile}"
        echo "--" >> "${logfile}"
    fi    
else
    echo "ERREUR : Architecture système non prise en charge. Ce script est destiné uniquement aux Mac Intel et ARM."
    echo "$(date): ERREUR : Architecture système non prise en charge. Ce script est destiné uniquement aux Mac Intel et ARM." >> "${logfile}"
fi

exit 0
