import numpy as np
import pandas as pd
from scipy import stats
from statsmodels.tsa.stattools import adfuller
from statsmodels.tsa.vector_ar.vecm import coint_johansen
from sklearn.decomposition import PCA
from sklearn.cluster import KMeans
from sklearn.ensemble import RandomForestClassifier
from filterpy.kalman import KalmanFilter
from hmmlearn import hmm
import json
import socket
import threading
import time

class QuantBackend:
    def __init__(self):
        # Initialisation des modèles
        self.kalman_filter = None
        self.hmm_model = None
        self.pca = PCA(n_components=3)
        self.kmeans = KMeans(n_clusters=3)
        self.rf_classifier = RandomForestClassifier(n_estimators=100)
        
        # Initialisation du stockage des données
        self.price_history = {}
        self.regime_history = []
        self.correlation_matrix = None
        
    def initialize_kalman_filter(self, initial_state, initial_covariance):
        """Initialiser le Filtre de Kalman pour l'estimation du spread"""
        self.kalman_filter = KalmanFilter(dim_x=2, dim_z=1)
        self.kalman_filter.x = initial_state
        self.kalman_filter.P = initial_covariance
        self.kalman_filter.H = np.array([[1., 0.]])
        self.kalman_filter.R = 0.1
        self.kalman_filter.Q = np.eye(2) * 0.01
        
    def calculate_zscore(self, spread):
        """Calculer le Z-score adaptatif en utilisant le Filtre de Kalman"""
        if self.kalman_filter is None:
            return 0.0
            
        self.kalman_filter.predict()
        self.kalman_filter.update(spread)
        
        mean = self.kalman_filter.x[0]
        std = np.sqrt(self.kalman_filter.P[0, 0])
        
        if std == 0:
            return 0.0
            
        return (spread - mean) / std
        
    def detect_cointegration(self, series1, series2):
        """Effectuer les tests de cointégration"""
        # Test ADF
        adf_result = adfuller(series1 - series2)
        
        # Test de Johansen
        data = np.column_stack((series1, series2))
        johansen_result = coint_johansen(data, det_order=0, k_ar_diff=1)
        
        return {
            'adf_pvalue': adf_result[1],
            'johansen_trace': johansen_result.lr1[0],
            'johansen_max_eig': johansen_result.lr2[0]
        }
        
    def detect_regime(self, price_data):
        """Détecter le régime du marché en utilisant HMM"""
        if len(self.regime_history) < 100:
            return False
            
        # Préparer les données pour HMM
        returns = np.diff(np.log(price_data))
        returns = returns.reshape(-1, 1)
        
        # Ajuster HMM s'il n'est pas déjà ajusté
        if self.hmm_model is None:
            self.hmm_model = hmm.GaussianHMM(n_components=2, covariance_type="full")
            self.hmm_model.fit(returns)
            
        # Prédire le régime
        regime = self.hmm_model.predict(returns)
        self.regime_history.append(regime[-1])
        
        # Considérer le régime comme directionnel s'il est stable
        if len(self.regime_history) >= 10:
            recent_regime = self.regime_history[-10:]
            return len(set(recent_regime)) == 1
            
        return False
        
    def calculate_pca_signals(self, price_matrix):
        """Calculer les signaux PCA pour plusieurs paires"""
        # Ajuster PCA
        self.pca.fit(price_matrix)
        
        # Obtenir les composantes principales
        components = self.pca.transform(price_matrix)
        
        # Calculer le momentum
        momentum = np.diff(components, axis=0)
        
        return {
            'components': components,
            'momentum': momentum,
            'explained_variance': self.pca.explained_variance_ratio_
        }
        
    def calculate_ml_probability(self, features):
        """Calculer la probabilité ML en utilisant Random Forest"""
        if not hasattr(self.rf_classifier, 'classes_'):
            return 0.5
            
        proba = self.rf_classifier.predict_proba(features.reshape(1, -1))
        return proba[0][1]  # Probabilité de la classe positive
        
    def calculate_hedge_ratio(self, pair1, pair2):
        """Calculer le ratio de couverture dynamique"""
        if len(pair1) < 2 or len(pair2) < 2:
            return 0.0
            
        # Calculer la corrélation glissante
        correlation = np.corrcoef(pair1, pair2)[0, 1]
        
        # Calculer le bêta
        beta = np.cov(pair1, pair2)[0, 1] / np.var(pair2)
        
        # Mettre à jour la matrice de corrélation
        if self.correlation_matrix is None:
            self.correlation_matrix = np.array([[1.0, correlation], [correlation, 1.0]])
        else:
            self.correlation_matrix = 0.95 * self.correlation_matrix + 0.05 * np.array([[1.0, correlation], [correlation, 1.0]])
            
        return {
            'correlation': correlation,
            'beta': beta,
            'hedge_ratio': beta * (np.std(pair1) / np.std(pair2))
        }
        
    def calculate_optimal_stop(self, position_data):
        """Calculer le temps d'arrêt optimal en utilisant HJB simplifié"""
        if len(position_data) < 2:
            return False
            
        # Calculer les rendements et la volatilité
        returns = np.diff(np.log(position_data))
        volatility = np.std(returns)
        
        # Condition HJB simplifiée
        expected_return = np.mean(returns)
        risk_aversion = 2.0  # Paramètre d'aversion au risque
        
        # Condition d'arrêt optimal
        stop_condition = expected_return - 0.5 * risk_aversion * volatility**2
        
        return stop_condition < 0
        
    def process_mt5_data(self, data_json):
        """Traiter les données de MT5 et renvoyer les signaux de trading"""
        try:
            data = json.loads(data_json)
            
            # Extraire les données de prix
            prices = np.array(data['prices'])
            volumes = np.array(data['volumes'])
            
            # Calculer les signaux
            zscore = self.calculate_zscore(prices[-1])
            regime = self.detect_regime(prices)
            
            # Calculer la probabilité ML
            features = np.column_stack((
                prices[-20:],
                volumes[-20:],
                np.diff(prices[-20:])
            ))
            ml_prob = self.calculate_ml_probability(features)
            
            # Calculer les signaux de couverture
            hedge_data = self.calculate_hedge_ratio(
                data.get('pair1_prices', prices),
                data.get('pair2_prices', prices)
            )
            
            # Calculer l'arrêt optimal
            stop_signal = self.calculate_optimal_stop(prices)
            
            # Préparer la réponse
            response = {
                'zScore': float(zscore),
                'isDirectionalRegime': bool(regime),
                'mlProbability': float(ml_prob),
                'kalmanSignal': bool(abs(zscore) > 2.0),
                'hedgeSignal': bool(hedge_data['correlation'] > 0.7),
                'correlation': float(hedge_data['correlation']),
                'optimalStopSignal': bool(stop_signal)
            }
            
            return json.dumps(response)
            
        except Exception as e:
            print(f"Erreur lors du traitement des données: {str(e)}")
            return json.dumps({
                'error': str(e)
            })

class MT5Server:
    def __init__(self, host='localhost', port=5555):
        self.host = host
        self.port = port
        self.quant = QuantBackend()
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.bind((self.host, self.port))
        self.server_socket.listen(1)
        
    def start(self):
        print(f"Serveur démarré sur {self.host}:{self.port}")
        while True:
            client_socket, address = self.server_socket.accept()
            print(f"Connecté à {address}")
            
            # Gérer le client dans un thread séparé
            client_thread = threading.Thread(
                target=self.handle_client,
                args=(client_socket,)
            )
            client_thread.start()
            
    def handle_client(self, client_socket):
        try:
            while True:
                # Recevoir les données de MT5
                data = client_socket.recv(4096)
                if not data:
                    break
                    
                # Traiter les données et obtenir les signaux
                response = self.quant.process_mt5_data(data.decode())
                
                # Envoyer la réponse à MT5
                client_socket.send(response.encode())
                
        except Exception as e:
            print(f"Erreur lors de la gestion du client: {str(e)}")
        finally:
            client_socket.close()

if __name__ == "__main__":
    server = MT5Server()
    server.start() 