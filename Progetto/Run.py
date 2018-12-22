from Progetto.utils.MatrixBuilder import Utils
from Progetto.utils.Evaluation import Eval
from Progetto.recommenders.Basic.Pure_SVD import PureSVD
from Progetto.recommenders.Basic.ICM_SVD import ItemSVD
from Progetto.recommenders.Basic.Item_CFR import Item_CFR
from Progetto.recommenders.Basic.Item_CBR import Item_CBR
from Progetto.recommenders.Basic.User_CFR import User_CFR
from Progetto.recommenders.Basic.P3Alfa import P3Alfa_R
from Progetto.recommenders.Basic.P3Beta import P3Beta_R
from Progetto.recommenders.Basic.Slim_BPR import Slim_BPR
from Progetto.recommenders.Basic.Slim_Elastic import Slim_Elastic
from Progetto.recommenders.Ensemble_post import Ensemble_post
import pandas as pd
import numpy as np
from tqdm import tqdm


class Recommender(object):

    def __init__(self):
        self.train = pd.read_csv("data/train.csv")
        self.tracks = pd.read_csv("data/tracks.csv")
        self.target_playlists = pd.read_csv("data/target_playlists.csv")
        self.train_sequential = pd.read_csv("data/train_sequential.csv")
        self.u = Utils(self.train, self.tracks, self.target_playlists, self.train_sequential)
        self.e = Eval(self.u, (np.random.choice(np.arange(10000), 5000, replace=False)).tolist())
        self.URM_full = self.u.get_URM()
        self.URM_train = self.e.get_URM_train()

    def generate_result(self, recommender, path, is_test = True):
        if is_test:
            return self.e.evaluate_algorithm(recommender)
        else:
            return self.generate_predictions(recommender, path)

    def generate_predictions(self, recommender, path):
        target_playlists = self.target_playlists
        final_result = pd.DataFrame(index=range(target_playlists.shape[0]), columns=('playlist_id', 'track_ids'))

        for i, target_playlist in tqdm(enumerate(np.array(target_playlists))):
            result_tracks = recommender.recommend(int(target_playlist))
            final_result['playlist_id'][i] = int(target_playlist)
            string_rec = ' '.join(map(str, result_tracks.reshape(1, 10)[0]))
            final_result['track_ids'][i] = string_rec

        final_result.to_csv(path, index=False)

    def recommend_itemCBR(self, knn=150, shrink=5, normalize=True, similarity='cosine', tfidf=True):
        rec = Item_CBR(self.u)
        rec.fit(self.URM_train, knn, shrink, normalize, similarity, tfidf)
        return self.generate_result(rec, None)

    def recommend_itemCFR(self, knn=150, shrink=10, normalize=True, similarity='cosine', tfidf=True):
        rec = Item_CFR(self.u)
        rec.fit(self.URM_train, knn, shrink, normalize, similarity, tfidf)
        return self.generate_result(rec, None)

    def recommend_userCFR(self, knn=150, shrink=10, normalize=True, similarity='cosine', tfidf=True):
        rec = User_CFR(self.u)
        rec.fit(self.URM_train, knn, shrink, normalize, similarity, tfidf)
        return self.generate_result(rec, None)

    def recommend_SlimBPR(self, knn=250, epochs=15, sgd_mode='adagrad', lr=0.1, lower=5, n_iter=1):
        rec = Slim_BPR(self.u)
        rec.fit(self.URM_train, knn, epochs, sgd_mode, lr, lower, n_iter)
        return self.generate_result(rec, None)

    def recommend_SlimElastic(self, knn=250, l1=1, po=True):
        rec = Slim_Elastic(self.u)
        rec.fit(self.URM_train, knn, l1, po)
        return self.generate_result(rec, None)

    def recommend_PureSVD(self, k=800, n_iter=1, random_state=False, bm25=True, K1=2, B=0.9):
        rec = PureSVD(self.u)
        rec.fit(self.URM_train, k, n_iter, random_state, bm25, K1, B)
        return self.generate_result(rec, None)

    def recommend_ItemSVD(self, k=300, knn=150, tfidf=True):
        rec = ItemSVD(self.u)
        rec.fit(self.URM_train, k, knn, tfidf)
        return self.generate_result(rec, None)

    def recommend_P3A(self, knn=60, alfa=0.7):
        rec = P3Alfa_R(self.u)
        rec.fit(self.URM_train, knn, alfa)
        return self.generate_result(rec, None)

    def recommend_P3B(self, knn=100, alfa=0.7, beta=0.3):
        rec = P3Beta_R(self.u)
        rec.fit(self.URM_train, knn, alfa, beta)
        return self.generate_result(rec, None)

    def recommend_ensemble_post(self, is_test=True, knn=(150, 150, 150, 250, 250, 80), shrink=(10, 10, 5),
                                weights=(1.65, 0.55, 1, 0.15, 0.05, 0), epochs=15, tfidf=True, n_iter=1):
        rec = Ensemble_post(self.u)
        if is_test:
            rec.fit(self.URM_train, knn, shrink, weights, epochs, tfidf, n_iter)
        else:
            rec.fit(self.URM_full, knn, shrink, weights, epochs, tfidf, n_iter)
        return self.generate_result(rec, "./predictions/ensemble_post", is_test)


if __name__ == '__main__':
    run = Recommender()
    run.recommend_ItemSVD(tfidf=False)
    run.recommend_ItemSVD(tfidf=False, k=500)
    run.recommend_ItemSVD(tfidf=True)













    







