# RobotQuant - Expert Advisor pour MetaTrader 5

Robot de trading quantitatif avancé combinant mean-reversion, filtrage de Kalman et machine learning pour MetaTrader 5.

## Fonctionnalités

- Mean-reversion avec filtre de Kalman adaptatif
- Détection de cointégration (ADF + Johansen)
- Analyse PCA
- Machine Learning (Random Forest)
- Gestion multi-positions
- Couverture locale delta
- Temps d'arrêt optimal
- Hedging et coverage sur paires corrélées

## Prérequis

- MetaTrader 5
- Python 3.8+
- Bibliothèques Python (voir requirements.txt)

## Installation

1. Copiez `RobotQuant.mq5` dans le dossier `MQL5/Experts` de MetaTrader 5
2. Installez les dépendances Python :

```bash
pip install -r requirements.txt
```

3. Démarrez le serveur Python :

```bash
python quant_backend.py
```

4. Redémarrez MetaTrader 5
5. Ajoutez l'Expert Advisor sur un graphique

## Configuration

### Paramètres MQL5

- `InpLotSize` : Taille du lot (défaut: 0.1)
- `InpZScoreThreshold` : Seuil Z-Score (défaut: 2.0)
- `InpPipsBeforeRecovery` : Pips avant reprise de position (défaut: 50)
- `InpMaxLossUSD` : Perte maximale en USD (défaut: 1000.0)
- `InpTakeProfitUSD` : Take Profit en USD (défaut: 2000.0)
- `InpMagicNumber` : Numéro magique (défaut: 123456)
- `InpMaxPositions` : Nombre maximum de positions (défaut: 5)
- `InpAdaptiveMAPeriod` : Période de la moyenne mobile adaptative (défaut: 20)
- `InpVolumeThreshold` : Seuil de volume (défaut: 1000)

### Configuration Python

Le serveur Python est par défaut sur `localhost:5555`. Pour modifier le port, éditez la variable `PORT` dans `quant_backend.py`.

## Utilisation

1. Démarrez le serveur Python
2. Ajoutez l'EA sur un graphique dans MT5
3. Configurez les paramètres selon vos besoins
4. Activez le trading automatique

## Sécurité

- Stops de sécurité intégrés
- Gestion des risques intégrée
- Limites de pertes configurables

## Auteur

Aaron Z.

## Licence

MIT
