# Installer BeatBitch sur iPhone / iPad

> BeatBitch n'est **pas** disponible sur l'App Store (l'App Store interdit le
> contenu pour adultes). Pour iOS, on passe par une **version web installable**
> (PWA). Une fois ajoutée à ton écran d'accueil, elle se comporte comme une
> vraie app : icône dédiée, plein écran, pas de barre Safari, fonctionne hors
> ligne après le premier chargement.

**Langues** : Français · [English](INSTALL-iOS.en.md) · [Deutsch](INSTALL-iOS.de.md)

---

## Avant de commencer

- Tu as besoin d'un **iPhone** ou **iPad** avec **iOS 16.4 ou plus récent**.
- Tu dois utiliser **Safari** (pas Chrome ni Firefox sur iOS — Apple n'autorise
  pas l'installation de PWA depuis ces navigateurs).
- Le premier chargement nécessite une **connexion Internet**. Ensuite, tout
  fonctionne hors ligne.

---

## Installation — pas à pas

### 1. Ouvre Safari et va à l'adresse

```
URL_BEATBITCH_PWA
```

(Remplace par l'URL communiquée par BB Studio.)

Patiente le temps que la page se charge complètement (quelques secondes : on
télécharge l'app entière, audio inclus, pour qu'elle marche hors ligne ensuite).

### 2. Touche l'icône **Partager**

C'est l'icône en bas de l'écran (au centre sur iPhone, en haut sur iPad) qui
ressemble à un carré avec une flèche pointant vers le haut :

```
   ┌──┐
   │↑ │
   └──┘
```

### 3. Fais défiler le menu de partage

Dans la liste des actions, cherche **« Sur l'écran d'accueil »** (icône **+**
sur un carré). Touche cette option.

> Si tu ne la vois pas, fais défiler vers le bas — selon ton iOS, elle peut
> être plus bas dans la liste.

### 4. Confirme le nom et touche **Ajouter**

iOS te propose le nom « BeatBitch ». Garde-le tel quel (ou modifie-le si tu
veux discrétion sur ton écran d'accueil — par exemple « Coach »).

Touche **Ajouter** en haut à droite.

### 5. Lance BeatBitch depuis l'icône

Quitte Safari. Tu trouves l'icône **BeatBitch** sur ton écran d'accueil, comme
n'importe quelle app. Touche-la : l'app démarre en plein écran, sans la barre
Safari, exactement comme une app native.

---

## Ce qu'il faut savoir

### Hors ligne

Après le premier lancement, BeatBitch fonctionne **sans réseau**. Tu peux
mettre ton iPhone en mode avion : tout marche.

### Mises à jour

Quand BB Studio publie une nouvelle version, ton iPhone la récupère
automatiquement au prochain lancement de l'app **avec une connexion**. Pas de
notification de mise à jour visible — c'est silencieux.

### Stockage : attention au délai de 7 semaines

iOS efface automatiquement le cache d'une PWA si tu **n'ouvres pas l'app
pendant ~7 semaines**. Quand ça arrive :

- L'app aura besoin d'une connexion Internet pour se recharger.
- **Ta progression de carrière sera perdue** (niveau, badges, milestones,
  surnoms, réglages).

> 💡 Ouvre BeatBitch au moins une fois par mois pour éviter ce reset.

### Différences avec la version Android

Quelques fonctions ne sont **pas disponibles** sur iOS PWA :

- **Vérif caméra des holds** — n'utilise pas la caméra.
- **Notifications surprise** — iOS ne permet pas les notifications planifiées
  pour les PWA aussi librement qu'Android.
- **Voix TTS** — tu n'as que les voix Apple installées sur ton iPhone
  (pas les voix Google d'Android). La qualité est correcte mais le ton peut
  être moins « ferme » qu'attendu.
- **Audio en arrière-plan** — Safari iOS peut couper l'audio si tu verrouilles
  l'écran. Garde l'écran allumé pendant ta session.

---

## Problèmes courants

### « L'option Sur l'écran d'accueil n'apparaît pas »

Tu n'es probablement pas dans Safari. Vérifie : si tu utilises Chrome ou
Firefox sur iPhone, ça ne marche pas. Ouvre l'URL **dans Safari**.

### « L'app ne se lance pas hors ligne »

Le premier chargement n'a pas réussi à mettre en cache toute l'app. Reconnecte
ton iPhone à Internet, ouvre BeatBitch, attends qu'elle charge complètement,
puis essaie à nouveau en mode avion.

### « Le son grésille / décroche »

Safari iOS a des limites sur l'audio en arrière-plan. Assure-toi que :

- L'écran reste allumé (paramètre **Réglages → Écran et luminosité → Verrouillage automatique → Jamais** pendant la session).
- Le volume média (pas sonnerie) est monté.
- Aucune autre app audio n'est en cours (musique, podcast).

### « Pas de son du tout »

iOS bloque parfois l'autoplay audio. Touche n'importe quel bouton de l'app une
fois (par exemple lance/arrête une session) pour débloquer l'audio.

---

## Désinstaller

Touche et maintiens l'icône **BeatBitch** sur l'écran d'accueil → **Supprimer
l'app** → **Supprimer**. Toutes les données locales sont effacées.

---

## Support

Repo GitHub : [github.com/bbstudioapp/beatbitch](https://github.com/bbstudioapp/beatbitch)
Issues : ouvre une issue en français ou en anglais.
