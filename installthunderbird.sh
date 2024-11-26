#!/bin/sh
#####################################################################################################
#
# ABOUT THIS PROGRAM
#
# NAME
#   ThunderbirdESRInstall.sh -- Installs or updates Thunderbird ESR with user approval via swiftDialog
#
# SYNOPSIS
#   sudo ThunderbirdESRInstall.sh
#
####################################################################################################
#
# HISTORY
#
#   Version: 2.5
#
#   - DJELAL Oussama, 2024-11-25
#   - Improved logic to compare version before downloading.
#
####################################################################################################
# Script to download and install Thunderbird ESR.
# Now supports Intel and ARM systems.
# User confirmation required via swiftDialog before proceeding with update.
#
# Choose language (en-US, fr, de, etc.)
lang="fr"  # Langue par défaut définie en français

echo "Démarrage du script d'installation/mise à jour de Thunderbird ESR..."

# VÉRIFICATION SI UNE VALEUR A ÉTÉ PASSÉE EN PARAMÈTRE 4 ET, LE CAS ÉCHÉANT, ASSIGNER À "lang"
if [ -n "$4" ]; then  # Vérifie si $4 n'est pas vide
    lang="$4"
    echo "Paramètre de langue détecté, définition de la langue sur $lang"
else
    echo "Aucun paramètre de langue fourni. Utilisation de la langue par défaut : $lang"
fi

dmgfile="TB.dmg"
logfile="/Library/Logs/ThunderbirdESRInstallScript.log"

echo "Fichier de log : $logfile"
echo "Vérification de l'architecture du système..."

# Vérifie si nous sommes sur Intel ou ARM en utilisant uname -m
arch=$(/usr/bin/uname -m )
echo "Architecture détectée : $arch"

if [ "$arch" = "i386" ] || [ "$arch" = "x86_64" ] || [ "$arch" = "arm64" ]; then
    echo "Architecture prise en charge : $arch"

    ## Obtenir la version du système d'exploitation et ajuster pour l'utilisation dans l'URL
    OSvers=$(sw_vers -productVersion)
    if [ -z "$OSvers" ]; then
        echo "Erreur : Impossible de déterminer la version du système d'exploitation."
        echo "$(date): ERREUR : Impossible de déterminer la version du système d'exploitation." >> "${logfile}"
        exit 1
    fi
    OSvers_URL=$(echo "$OSvers" | sed 's/[.]/_/g')
    echo "Version du système d'exploitation : $OSvers (format URL : $OSvers_URL)"

    ## Définir la chaîne User Agent pour utiliser avec curl
    userAgent="Mozilla/5.0 (Macintosh; ${arch} Mac OS X ${OSvers_URL}) AppleWebKit/535.6.2 (KHTML, like Gecko) Version/5.2 Safari/535.6.2"
    echo "User Agent défini pour curl : $userAgent"

    # Obtenir la dernière version ESR de Thunderbird disponible depuis la page de Thunderbird ESR
    echo "Récupération des informations de la dernière version ESR de Thunderbird..."

    # Utiliser curl pour suivre les redirections et obtenir l'URL finale du DMG de la version ESR
    download_url=$(curl -s -L -A "$userAgent" -o /dev/null -w '%{url_effective}' "https://download.mozilla.org/?product=thunderbird-esr-latest-ssl&os=osx&lang=${lang}")

    if [ -z "$download_url" ]; then
        echo "Erreur : Impossible de récupérer l'URL de téléchargement de Thunderbird ESR."
        echo "$(date): ERREUR : Impossible de récupérer l'URL de téléchargement de Thunderbird ESR." >> "${logfile}"
        exit 1
    fi

    echo "URL de téléchargement obtenue : $download_url"

    # Extraire la version avec une expression régulière sans télécharger le DMG
    latestver=$(echo "$download_url" | grep -o 'Thunderbird%20[0-9]\+\.[0-9]\+\.[0-9]\+' | sed 's/Thunderbird%20//' | xargs)

    if [ -z "$latestver" ]; then
        echo "Erreur : Impossible d'extraire la version de Thunderbird à partir de l'URL."
        echo "$(date): ERREUR : Impossible d'extraire la version de Thunderbird à partir de l'URL." >> "${logfile}"
        exit 1
    fi

    echo "Dernière version ESR disponible de Thunderbird : $latestver"

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

    # Comparer les deux versions. Si elles sont différentes ou si Thunderbird n'est pas présent, demander la confirmation à l'utilisateur et télécharger et installer la nouvelle version.
    if [ "$currentinstalledver" = "$latestver" ]; then
        echo "Thunderbird ESR est déjà à jour, version actuelle : ${currentinstalledver}."
        echo "$(date): Thunderbird ESR est déjà à jour, version actuelle : ${currentinstalledver}." >> "${logfile}"
        exit 0
    fi

    if [ "$currentinstalledver" = "none" ] || [ "$currentinstalledver" != "$latestver" ]; then
        # Demande de confirmation à l'utilisateur avant de continuer
        /usr/local/bin/dialog --title "Mise à jour de Thunderbird ESR" --message "Une nouvelle version de Thunderbird ESR est disponible. Souhaitez-vous mettre à jour maintenant ?

Attention : ceci redémarrera votre messagerie" --icon "/usr/local/share/brandingimage.png" --button1text "Mettre à jour" --button2text "Annuler"
        user_choice=$?

        if [ "$user_choice" -ne 0 ]; then
            echo "Mise à jour annulée par l'utilisateur. Fin du script."
            echo "$(date): Mise à jour annulée par l'utilisateur." >> ${logfile}
            exit 0
        fi

        /bin/sleep 5

        # Assurer que Thunderbird est fermé avant de désinstaller
        echo "Vérification et fermeture de Thunderbird s'il est en cours d'exécution..."
        sudo /usr/bin/osascript -e 'tell application "Thunderbird" to quit'
        /bin/sleep 5
        /usr/bin/pgrep Thunderbird && sudo /usr/bin/pkill -9 Thunderbird
        if [ $? -eq 0 ]; then
            echo "Thunderbird fermé avec succès."
            echo "$(date): Thunderbird fermé avant la désinstallation." >> "${logfile}"
        fi

        # Si Thunderbird est déjà installé, le supprimer
        if [ -d "/Applications/Thunderbird.app" ]; then
            echo "Suppression de la version actuelle de Thunderbird..."
            sudo /bin/rm -rf "/Applications/Thunderbird.app"
            if [ $? -eq 0 ]; then
                echo "Thunderbird supprimé avec succès."
                echo "$(date): Thunderbird supprimé avant la nouvelle installation." >> "${logfile}"
            else
                echo "Erreur : Échec de la suppression de Thunderbird."
                echo "$(date): ERREUR : Échec de la suppression de Thunderbird." >> "${logfile}"
                exit 1
            fi
        fi

        url="$download_url"
        
        echo "URL de téléchargement de la dernière version : $url"
        echo "$(date): URL de téléchargement : $url" >> "${logfile}"

        echo "Téléchargement et installation de Thunderbird ESR en cours..."
        
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
        
        sudo rsync -a --delete "/Volumes/Thunderbird/Thunderbird.app/" "/Applications/Thunderbird.app/"
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
        if [ "$latestver" = "$newlyinstalledver" ]; then
            echo "SUCCESS : Thunderbird ESR a été mis à jour à la version ${newlyinstalledver}"
            echo "$(date): SUCCESS: Thunderbird ESR a été mis à jour à la version ${newlyinstalledver}" >> "${logfile}"
            /usr/local/bin/dialog --title "Installation réussie" --message "Thunderbird ESR a été mis à jour avec succès à la version ${newlyinstalledver}." --button1text "OK"
        else
            echo "ERREUR : Mise à jour de Thunderbird échouée, la version reste à ${currentinstalledver}."
            echo "$(date): ERREUR: Mise à jour de Thunderbird échouée, la version reste à ${currentinstalledver}." >> "${logfile}"
            echo "--" >> "${logfile}"
            /usr/local/bin/dialog --title "Échec de l'installation" --message "La mise à jour de Thunderbird ESR a échoué. La version actuelle reste ${currentinstalledver}." --button1text "OK"
            exit 1
        fi
    fi    
else
    echo "ERREUR : Architecture système non prise en charge. Ce script est destiné uniquement aux Mac Intel et ARM."
    echo "$(date): ERREUR : Architecture système non prise en charge. Ce script est destiné uniquement aux Mac Intel et ARM." >> "${logfile}"
    /usr/local/bin/dialog --title "Erreur d'installation" --message "Architecture système non prise en charge. Ce script est destiné uniquement aux Mac Intel et ARM." --button1text "OK"
fi

exit 0
