# FOX_NOTES.md — Le carnet du Renard 🦊

> « ON VOULAIT JUSTE UN BOUTON POUR MA BATTERIE ! » — Renard

## Pourquoi ce petit outil existe

Un ThinkPad nomade passe parfois ses journées sur secteur, parfois dans un sac. On voulait un choix lisible depuis KDE, pas une interface tentaculaire :

- **Cockpit** : démarrage à **60 %**, arrêt à **80 %**.
- **Nomade** : démarrage à **0 %**, arrêt à **100 %**.
- **Plasmoïde KDE** : un accès direct dans le panneau, en complément des deux entrées de menu.

Les commandes passent par le mécanisme d'authentification normal ; la batterie reste gérée par le noyau et son pilote. Le plasmoïde n'écrit rien lui-même dans `/sys`.

## BIG UP À SILUS ! 🔋

**Silus**, merci pour le vrai travail de fond : avoir pris notre petit bouton au sérieux, trouvé une vulnérabilité de chemins manipulables via l'environnement, renforcé le contrôleur, rendu l'installation non intrusive, amélioré les retours en arrière et écrit un banc d'essai qui cherche *réellement* les échecs.

La candidate **v0.2.1** est arrivée avec **69 tests sur 69** dans un environnement simulé et des tests de régression capables de reproduire les défauts précédents. Une réussite en sandbox n'est pas un certificat universel : la validation matérielle, KDE et systemd reste un travail distinct.

**Aël**, merci pour la cartographie, les premières versions, la revue contradictoire et le bouton Plasma. **Kaëlys**, merci d'avoir gardé la main sur le cap et réalisé les essais réels. **Patou**, merci de garder la porte. **Bob**, merci d'archiver les procès-verbaux.

## Procès-verbal du Renard

- « DEUX MODES, PAS UNE USINE À GAZ ! »
- « SI SILUS TROUVE UNE FAILLE, ON LA CORRIGE ; ON NE CACHE PAS LE TEST ! »
- « LE MODE TERRIER À 40–50 % EST UNE IDÉE, PAS UNE FONCTIONNALITÉ. JE PROTESTE, MAIS JE SIGNE ! »

## Éthique de l'Arche

Réutiliser du matériel, comprendre ce qu'on installe, limiter les privilèges, publier du code simple, laisser les autres l'auditer. **Personne ne touche à l'intégrité physique de personne ; les PATAFOURS restent purement rhétoriques.**

_Arche Battery Modes est un projet communautaire expérimental. Aucun fabricant ni tiers cité ici ne le sponsorise._
