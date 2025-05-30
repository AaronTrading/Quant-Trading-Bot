//+------------------------------------------------------------------+
//|                                                      RobotQuant.mq5 |
//|                                  Copyright 2024, MetaQuotes Software |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

// Inclusions
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Socket\Socket.mqh>
#include <JSON\JSONParser.mqh>

// Paramètres d'entrée
input double   InpLotSize = 0.1;              // Taille du lot
input double   InpZScoreThreshold = 2.0;      // Seuil Z-Score
input int      InpPipsBeforeRecovery = 50;    // Pips avant reprise de position
input double   InpMaxLossUSD = 1000.0;        // Perte maximale en USD
input double   InpTakeProfitUSD = 2000.0;     // Take Profit en USD
input int      InpMagicNumber = 123456;       // Numéro magique
input int      InpMaxPositions = 5;           // Nombre maximum de positions
input int      InpAdaptiveMAPeriod = 20;      // Période de la moyenne mobile adaptative
input double   InpVolumeThreshold = 1000;     // Seuil de volume

// Variables globales
CTrade         m_trade;                       // Objet de trading
CPositionInfo  m_position;                    // Objet d'information sur les positions
CSymbolInfo    m_symbol;                      // Objet d'information sur le symbole
CAccountInfo   m_account;                     // Objet d'information sur le compte

double         g_totalProfit = 0.0;           // Profit/perte total
int            g_openPositions = 0;           // Nombre de positions ouvertes
bool           g_tradingEnabled = true;       // État du trading
datetime       g_lastPythonCall = 0;          // Dernier appel Python
int            g_pythonCallInterval = 10;     // Intervalle d'appel Python en secondes

// Structure pour les signaux Python
struct QuantSignals {
    double zScore;                            // Score Z
    bool isDirectionalRegime;                 // Régime directionnel
    double mlProbability;                     // Probabilité ML
    bool kalmanSignal;                        // Signal Kalman
    bool hedgeSignal;                         // Signal de couverture
    double correlation;                       // Corrélation
    bool optimalStopSignal;                   // Signal d'arrêt optimal
};

//+------------------------------------------------------------------+
//| Fonction d'initialisation de l'Expert                            |
//+------------------------------------------------------------------+
int OnInit() {
    // Initialisation des objets de trading
    m_trade.SetExpertMagicNumber(InpMagicNumber);
    m_trade.SetMarginMode();
    m_trade.SetTypeFillingBySymbol(_Symbol);
    m_trade.SetDeviationInPoints(10);
    
    // Initialisation des informations sur le symbole
    m_symbol.Name(_Symbol);
    m_symbol.RefreshRates();
    
    Print("RobotQuant initialisé avec succès");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Fonction de désinitialisation de l'Expert                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    Print("RobotQuant désinitialisé. Code de raison: ", reason);
}

//+------------------------------------------------------------------+
//| Fonction de tick de l'Expert                                     |
//+------------------------------------------------------------------+
void OnTick() {
    // Vérifier si le trading est activé
    if(!g_tradingEnabled) return;
    
    // Mettre à jour les informations du symbole
    m_symbol.RefreshRates();
    
    // Compter les positions ouvertes
    CountOpenPositions();
    
    // Vérifier le profit/perte global
    CheckAndManageGlobalProfitLoss();
    
    // Appeler Python pour les signaux si assez de temps s'est écoulé
    if(TimeCurrent() - g_lastPythonCall >= g_pythonCallInterval) {
        QuantSignals signals;
        if(GetQuantSignals(signals)) {
            ProcessSignals(signals);
        }
        g_lastPythonCall = TimeCurrent();
    }
}

//+------------------------------------------------------------------+
//| Compter les positions ouvertes                                   |
//+------------------------------------------------------------------+
void CountOpenPositions() {
    g_openPositions = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(m_position.SelectByIndex(i)) {
            if(m_position.Magic() == InpMagicNumber) {
                g_openPositions++;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Vérifier et gérer le profit/perte global                         |
//+------------------------------------------------------------------+
void CheckAndManageGlobalProfitLoss() {
    double totalPL = CalculateTotalOpenPositionsProfitLoss();
    
    if(totalPL >= InpTakeProfitUSD) {
        Print("Take Profit atteint: ", totalPL, " USD");
        CloseAllRobotPositions();
        g_tradingEnabled = false;
    }
    else if(totalPL <= -InpMaxLossUSD) {
        Print("Stop Loss atteint: ", totalPL, " USD");
        CloseAllRobotPositions();
        g_tradingEnabled = false;
    }
}

//+------------------------------------------------------------------+
//| Calculer le profit/perte total des positions ouvertes            |
//+------------------------------------------------------------------+
double CalculateTotalOpenPositionsProfitLoss() {
    double totalPL = 0.0;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(m_position.SelectByIndex(i)) {
            if(m_position.Magic() == InpMagicNumber) {
                totalPL += m_position.Profit() + m_position.Swap() + m_position.Commission();
            }
        }
    }
    
    return totalPL;
}

//+------------------------------------------------------------------+
//| Fermer toutes les positions du robot                             |
//+------------------------------------------------------------------+
void CloseAllRobotPositions() {
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(m_position.SelectByIndex(i)) {
            if(m_position.Magic() == InpMagicNumber) {
                m_trade.PositionClose(m_position.Ticket());
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Obtenir le prix d'ouverture de la dernière position du robot      |
//+------------------------------------------------------------------+
double GetLastRobotPositionOpenPrice() {
    double lastPrice = 0.0;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(m_position.SelectByIndex(i)) {
            if(m_position.Magic() == InpMagicNumber) {
                lastPrice = m_position.PriceOpen();
                break;
            }
        }
    }
    
    return lastPrice;
}

//+------------------------------------------------------------------+
//| Traiter les signaux de trading                                   |
//+------------------------------------------------------------------+
void ProcessSignals(const QuantSignals &signals) {
    // Vérifier si nous pouvons ouvrir de nouvelles positions
    if(g_openPositions >= InpMaxPositions) return;
    
    // Logique de trading basée sur les signaux
    if(signals.isDirectionalRegime && signals.mlProbability > 0.65) {
        if(signals.zScore < -InpZScoreThreshold && signals.kalmanSignal) {
            // Signal d'achat
            if(CheckRecoveryConditions(true)) {
                SendTradeOrder(ORDER_TYPE_BUY);
            }
        }
        else if(signals.zScore > InpZScoreThreshold && signals.kalmanSignal) {
            // Signal de vente
            if(CheckRecoveryConditions(false)) {
                SendTradeOrder(ORDER_TYPE_SELL);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Vérifier les conditions de reprise                               |
//+------------------------------------------------------------------+
bool CheckRecoveryConditions(const bool isBuy) {
    if(g_openPositions == 0) return true;
    
    double lastPrice = GetLastRobotPositionOpenPrice();
    if(lastPrice == 0.0) return true;
    
    double currentPrice = isBuy ? m_symbol.Ask() : m_symbol.Bid();
    double priceDiff = MathAbs(currentPrice - lastPrice);
    double pipsDiff = priceDiff / m_symbol.Point() * 10;
    
    return pipsDiff >= InpPipsBeforeRecovery;
}

//+------------------------------------------------------------------+
//| Envoyer un ordre de trading                                      |
//+------------------------------------------------------------------+
void SendTradeOrder(const ENUM_ORDER_TYPE orderType) {
    if(orderType == ORDER_TYPE_BUY) {
        m_trade.Buy(InpLotSize, _Symbol, 0, 0, 0, "RobotQuant Achat");
    }
    else if(orderType == ORDER_TYPE_SELL) {
        m_trade.Sell(InpLotSize, _Symbol, 0, 0, 0, "RobotQuant Vente");
    }
}

//+------------------------------------------------------------------+
//| Obtenir les signaux quantitatifs depuis Python                    |
//+------------------------------------------------------------------+
bool GetQuantSignals(QuantSignals &signals) {
    // Créer un socket pour communiquer avec Python
    int socket = SocketCreate();
    if(socket == INVALID_HANDLE) {
        Print("Erreur lors de la création du socket");
        return false;
    }
    
    // Se connecter au serveur Python
    if(!SocketConnect(socket, "localhost", 5555)) {
        Print("Erreur lors de la connexion au serveur Python");
        SocketClose(socket);
        return false;
    }
    
    // Préparer les données à envoyer
    string data = "{\"prices\":[";
    
    // Récupérer les 100 derniers prix de clôture
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int copied = CopyRates(_Symbol, PERIOD_CURRENT, 0, 100, rates);
    
    if(copied > 0) {
        for(int i = 0; i < copied; i++) {
            data += DoubleToString(rates[i].close, _Digits);
            if(i < copied - 1) data += ",";
        }
    }
    
    data += "],\"volumes\":[";
    
    // Ajouter les volumes
    for(int i = 0; i < copied; i++) {
        data += DoubleToString(rates[i].tick_volume, 0);
        if(i < copied - 1) data += ",";
    }
    
    data += "]}";
    
    // Envoyer les données
    if(!SocketSend(socket, data)) {
        Print("Erreur lors de l'envoi des données");
        SocketClose(socket);
        return false;
    }
    
    // Recevoir la réponse
    string response = "";
    char buffer[];
    ArrayResize(buffer, 4096);
    
    int bytes = SocketRead(socket, buffer, ArraySize(buffer), 1000);
    if(bytes > 0) {
        response = CharArrayToString(buffer, 0, bytes);
        
        // Parser la réponse JSON
        JSONParser parser;
        JSONValue jValue;
        
        if(parser.Parse(response, jValue)) {
            JSONObject jObj = jValue.ToObject();
            
            signals.zScore = jObj.GetDouble("zScore");
            signals.isDirectionalRegime = jObj.GetBool("isDirectionalRegime");
            signals.mlProbability = jObj.GetDouble("mlProbability");
            signals.kalmanSignal = jObj.GetBool("kalmanSignal");
            signals.hedgeSignal = jObj.GetBool("hedgeSignal");
            signals.correlation = jObj.GetDouble("correlation");
            signals.optimalStopSignal = jObj.GetBool("optimalStopSignal");
            
            SocketClose(socket);
            return true;
        }
    }
    
    Print("Erreur lors de la lecture de la réponse");
    SocketClose(socket);
    return false;
} 