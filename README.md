# Faxel 📲

**Faxel** est une application pour **iPhone et Android** qui réunit un navigateur avec téléchargement intégré, un lecteur vidéo/audio et une bibliothèque pour ranger ses fichiers, le tout en français. Un seul dépôt sert les deux plateformes.

## 📲 Installation

Faxel n'est pas sur l'App Store ni sur le Play Store : on l'installe soi-même avec un fichier d'installation, à télécharger dans les [**Releases**](https://github.com/Faxelh/Faxel/releases) du dépôt.

### 🤖 Android

1. Sur votre téléphone, ouvrez la page [**Releases**](https://github.com/Faxelh/Faxel/releases) et téléchargez le fichier **`.apk`** de la dernière version.
2. Ouvrez le fichier téléchargé (depuis la notification ou l'app *Fichiers*).
3. Si Android demande une autorisation, activez **« Autoriser depuis cette source »** pour votre navigateur ou votre gestionnaire de fichiers, puis revenez en arrière.
4. Touchez **Installer**. Si Play Protect affiche un avertissement, choisissez **« Installer quand même »**.
5. Ouvrez **Faxel** : c'est prêt.

### 🍎 iPhone

Il faut un ordinateur (Windows ou Mac) pour la première installation, avec **Sideloadly**.

1. Téléchargez le fichier **`.ipa`** de la dernière version dans les [**Releases**](https://github.com/Faxelh/Faxel/releases).
2. Installez [**Sideloadly**](https://sideloadly.io/) sur votre ordinateur.
   *Sous Windows, installez aussi iTunes et iCloud depuis le site d'Apple (pas depuis le Microsoft Store).*
3. Branchez votre iPhone avec un câble et touchez **Se fier** sur l'iPhone si la question s'affiche.
4. Ouvrez Sideloadly, glissez le fichier `.ipa` dans la fenêtre et saisissez votre identifiant Apple.
5. Cliquez sur **Start** et attendez la fin de l'installation.
6. Sur l'iPhone, allez dans **Réglages › Général › VPN et gestion de l'appareil**, touchez votre identifiant Apple puis **Faire confiance**.
7. Sur iOS 16 ou plus récent, activez aussi **Réglages › Confidentialité et sécurité › Mode développeur**, puis redémarrez l'iPhone.
8. Ouvrez **Faxel**.

> ⚠️ Avec un identifiant Apple gratuit, l'app expire au bout de **7 jours** : il faut la réinstaller avec Sideloadly. Pour éviter cela, utilisez **SideStore** ou **AltStore**, qui renouvellent l'app automatiquement.

### ✅ Vérifier que ça marche

Allez dans **Réglages** de l'application : le numéro de version s'affiche (par exemple `2026.10.3`).


## ✨ Fonctionnalités

### ⬇️ Téléchargement
- Navigateur intégré : à la question « Voulez-vous télécharger ce contenu ? », la vidéo part directement dans la file de téléchargement
- Vous restez dans le navigateur pour continuer à défiler et en ajouter d'autres
- Les formats sans filigrane sont choisis en priorité
- Sur Android : toucher le bouton de téléchargement ajoute à la file, un appui long permet de choisir la qualité

### 🎬 Lecteur vidéo
- Luminosité (glisser à gauche) et volume (glisser à droite)
- Appui long pour la vitesse ×2, glisser pour avancer ou reculer
- Carte « Épisode suivant » avec décompte
- Répétition, minuterie et capture d'écran
- L'écran ne se met pas en veille pendant la lecture

### 📚 Bibliothèque
- Vidéos, sons et photos au même endroit
- **Sélection multiple** : bouton « Sélectionner » ou appui long, puis « Tout sélectionner »
- Actions groupées : exporter vers la galerie, enregistrer dans un dossier (Fichiers), partager ou supprimer

### 🫥 Retrait de filigrane
- Floutez une ou plusieurs zones d'une vidéo

### ⚙️ Réglages
- Nom de l'application modifiable
- Icône personnalisée sur l'écran d'accueil
- Historique des nouveautés et liste des correctifs à chaque mise à jour

## 🔄 Mises à jour intégrées

L'application vérifie les nouvelles versions et propose de se mettre à jour.

| Plateforme | Méthode |
|---|---|
| 🍎 iPhone | SideStore / AltStore, ou IPA avec Sideloadly |
| 🤖 Android | Téléchargement et installation de l'APK depuis l'app |

## 🔢 Versions

Numérotation automatique **Année.Mois.N** : `2026.10.3` correspond à la 3e mise à jour d'octobre 2026.
Le détail de chaque version est dans [`HISTORIQUE.json`](HISTORIQUE.json).

## 📁 Structure du dépôt

```
├── android/            Application Android
├── ios/                Application iPhone
├── src/faxel/          Code source
├── tests/              Tests
├── assets/             Ressources
├── .github/workflows/  Compilation automatique
├── HISTORIQUE.json     Historique des nouveautés
└── VERSION             Numéro de version
```


## 👤 Auteur
Créé par **Faxel Kwadio** — [@Faxelh](https://github.com/Faxelh)
Développeur autodidacte, je crée des applications utiles pour mon quotidien et celui des autres.

## 🚀 Mes projets
| Projet | Description |
|---|---|
| [**Elara**](https://github.com/Faxelh/elara) | Application iPhone : lecteur vidéo/audio, dossier privé, compression, transfert Wi‑Fi |
| [**Music**](https://github.com/Faxelh/Music) | **Music** est un lecteur de musique pour **iPhone et Android**, en français : bibliothèque, lecteur complet, égaliseur, paroles, playlists et mix automatiques. Un seul dépôt sert les deux plateformes. |


## 🛠️ Technologies
![Swift](https://img.shields.io/badge/Swift-FA7343?style=flat&logo=swift&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?style=flat&logo=python&logoColor=white)
![Django](https://img.shields.io/badge/Django-092E20?style=flat&logo=django&logoColor=white)
![Git](https://img.shields.io/badge/Git-F05032?style=flat&logo=git&logoColor=white)
![VS Code](https://img.shields.io/badge/VS_Code-007ACC?style=flat&logo=visualstudiocode&logoColor=white)
