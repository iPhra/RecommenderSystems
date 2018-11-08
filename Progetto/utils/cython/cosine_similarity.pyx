"""
Created on 23/10/17

@author: Maurizio Ferrari Dacrema
"""

#cython: boundscheck=False
#cython: wraparound=True
#cython: initializedcheck=False
#cython: language_level=3
#cython: nonecheck=False
#cython: cdivision=True
#cython: unpack_method_calls=True
#cython: overflowcheck=False


import time, sys

import numpy as np
cimport numpy as np
from cpython.array cimport array, clone



import scipy.sparse as sps
#from Base.Recommender_utils import check_matrix


cdef class Cosine_Similarity:

    cdef int TopK
    cdef long n_items, n_users

    cdef int[:] user_to_item_row_ptr, user_to_item_cols
    cdef int[:] item_to_user_rows, item_to_user_col_ptr
    cdef double[:] user_to_item_data, item_to_user_data
    cdef double[:] sumOfSquared
    cdef int shrink, normalize, adjusted_cosine, pearson_correlation, tanimoto_coefficient

    cdef double[:,:] W_dense

    def __init__(self, URM, topK = 100, shrink=0, normalize = True,
                 mode = "cosine"):
        """
        Computes the cosine similarity on the columns of dataMatrix
        If it is computed on URM=|users|x|items|, pass the URM as is.
        If it is computed on ICM=|items|x|features|, pass the ICM transposed.
        :param dataMatrix:
        :param topK:
        :param shrink:
        :param normalize:
        :param mode:    "cosine"    computes Cosine similarity
                        "adjusted"  computes Adjusted Cosine, removing the average of the users
                        "pearson"   computes Pearson Correlation, removing the average of the items
                        "jaccard"   computes Jaccard similarity for binary interactions using Tanimoto
                        "tanimoto"  computes Tanimoto coefficient for binary interactions

        """

        super(Cosine_Similarity, self).__init__()

        self.n_items = URM.shape[1]
        self.n_users = URM.shape[0]
        self.shrink = shrink
        self.normalize = normalize

        self.adjusted_cosine = False
        self.pearson_correlation = False
        self.tanimoto_coefficient = False

        if mode == "adjusted":
            self.adjusted_cosine = True
        elif mode == "pearson":
            self.pearson_correlation = True
        elif mode == "jaccard" or mode == "tanimoto":
            self.tanimoto_coefficient = True
            # Tanimoto has a specific kind of normalization
            self.normalize = False

        elif mode == "cosine":
            pass
        else:
            raise ValueError("Cosine_Similarity: value for paramether 'mode' not recognized."
                             " Allowed values are: 'cosine', 'pearson', 'adjusted', 'jaccard', 'tanimoto'."
                             " Passed value was '{}'".format(mode))


        self.TopK = min(topK, self.n_items)

        # Copy data to avoid altering the original object
        URM = URM.copy()

        if self.adjusted_cosine:
            URM = self.applyAdjustedCosine(URM)
        elif self.pearson_correlation:
            URM = self.applyPearsonCorrelation(URM)
        elif self.tanimoto_coefficient:
            URM = self.useOnlyBooleanInteractions(URM)


        URM = URM.tocsr()

        self.user_to_item_row_ptr = URM.indptr
        self.user_to_item_cols = URM.indices
        self.user_to_item_data = np.array(URM.data, dtype=np.float64)

        URM = URM.tocsc()
        self.item_to_user_rows = URM.indices
        self.item_to_user_col_ptr = URM.indptr
        self.item_to_user_data = np.array(URM.data, dtype=np.float64)

        # Compute sum of squared values to be used in normalization
        self.sumOfSquared = np.array(URM.power(2).sum(axis=0), dtype=np.float64).ravel()

        # Tanimoto does not require the square root to be applied
        if not self.tanimoto_coefficient:
            self.sumOfSquared = np.sqrt(self.sumOfSquared)


        if self.TopK == 0:
            self.W_dense = np.zeros((self.n_items,self.n_items))


    cdef useOnlyBooleanInteractions(self, URM):
        """
        Set to 1 all data points
        :return:
        """

        cdef long index

        for index in range(len(URM.data)):
            URM.data[index] = 1

        return URM



    cdef applyPearsonCorrelation(self, URM):
        """
        Remove from every data point the average for the corresponding column
        :return:
        """

        cdef double[:] sumPerCol
        cdef int[:] interactionsPerCol
        cdef long colIndex, innerIndex, start_pos, end_pos
        cdef double colAverage


        URM = URM.tocsc()


        sumPerCol = np.array(URM.sum(axis=0), dtype=np.float64).ravel()
        interactionsPerCol = np.diff(URM.indptr)


        #Remove for every row the corresponding average
        for colIndex in range(self.n_items):

            if interactionsPerCol[colIndex]>0:

                colAverage = sumPerCol[colIndex] / interactionsPerCol[colIndex]

                start_pos = URM.indptr[colIndex]
                end_pos = URM.indptr[colIndex+1]

                innerIndex = start_pos

                while innerIndex < end_pos:

                    URM.data[innerIndex] -= colAverage
                    innerIndex+=1


        return URM



    cdef applyAdjustedCosine(self, URM):
        """
        Remove from every data point the average for the corresponding row
        :return:
        """

        cdef double[:] sumPerRow
        cdef int[:] interactionsPerRow
        cdef long rowIndex, innerIndex, start_pos, end_pos
        cdef double rowAverage

        URM = URM.tocsr()

        sumPerRow = np.array(URM.sum(axis=1), dtype=np.float64).ravel()
        interactionsPerRow = np.diff(URM.indptr)


        #Remove for every row the corresponding average
        for rowIndex in range(self.n_users):

            if interactionsPerRow[rowIndex]>0:

                rowAverage = sumPerRow[rowIndex] / interactionsPerRow[rowIndex]

                start_pos = URM.indptr[rowIndex]
                end_pos = URM.indptr[rowIndex+1]

                innerIndex = start_pos

                while innerIndex < end_pos:

                    URM.data[innerIndex] -= rowAverage
                    innerIndex+=1


        return URM





    cdef int[:] getUsersThatRatedItem(self, long item_id):
        return self.item_to_user_rows[self.item_to_user_col_ptr[item_id]:self.item_to_user_col_ptr[item_id+1]]

    cdef int[:] getItemsRatedByUser(self, long user_id):
        return self.user_to_item_cols[self.user_to_item_row_ptr[user_id]:self.user_to_item_row_ptr[user_id+1]]







    cdef double[:] computeItemSimilarities(self, long item_id_input):
        """
        For every item the cosine similarity against other items depends on whether they have users in common. The more
        common users the higher the similarity.
        
        The basic implementation is:
        - Select the first item
        - Loop through all other items
        -- Given the two items, get the users they have in common
        -- Update the similarity for all common users
        
        That is VERY slow due to the common user part, in which a long data structure is looped multiple times.
        
        A better way is to use the data structure in a different way skipping the search part, getting directly the
        information we need.
        
        The implementation here used is:
        - Select the first item
        - Initialize a zero valued array for the similarities
        - Get the users who rated the first item
        - Loop through the users
        -- Given a user, get the items he rated (second item)
        -- Update the similarity of the items he rated
        
        
        """

        # Create template used to initialize an array with zeros
        # Much faster than np.zeros(self.n_items)
        cdef array[double] template_zero = array('d')
        cdef array[double] result = clone(template_zero, self.n_items, zero=True)


        cdef long user_index, user_id, item_index, item_id_second

        cdef int[:] users_that_rated_item = self.getUsersThatRatedItem(item_id_input)
        cdef int[:] items_rated_by_user

        cdef double rating_item_input, rating_item_second

        # Get users that rated the items
        for user_index in range(len(users_that_rated_item)):

            user_id = users_that_rated_item[user_index]
            rating_item_input = self.item_to_user_data[self.item_to_user_col_ptr[item_id_input]+user_index]

            # Get all items rated by that user
            items_rated_by_user = self.getItemsRatedByUser(user_id)

            for item_index in range(len(items_rated_by_user)):

                item_id_second = items_rated_by_user[item_index]

                # Do not compute the similarity on the diagonal
                if item_id_second != item_id_input:
                    # Increment similairty
                    rating_item_second = self.user_to_item_data[self.user_to_item_row_ptr[user_id]+item_index]

                    result[item_id_second] += rating_item_input*rating_item_second

        return result




    def compute_similarity(self):

        cdef int itemIndex, innerItemIndex
        cdef long long topKItemIndex

        cdef long long[:] top_k_idx

        # Declare numpy data type to use vetor indexing and simplify the topK selection code
        cdef np.ndarray[long, ndim=1] top_k_partition, top_k_partition_sorting
        cdef np.ndarray[np.float64_t, ndim=1] this_item_weights_np

        cdef double[:] this_item_weights

        cdef long processedItems = 0

        # Data structure to incrementally build sparse matrix
        # Preinitialize max possible length
        cdef double[:] values = np.zeros((self.n_items*self.TopK))
        cdef int[:] rows = np.zeros((self.n_items*self.TopK,), dtype=np.int32)
        cdef int[:] cols = np.zeros((self.n_items*self.TopK,), dtype=np.int32)
        cdef long sparse_data_pointer = 0



        start_time = time.time()

        # Compute all similarities for each item
        for itemIndex in range(self.n_items):

            processedItems += 1

            if processedItems % 10000==0 or processedItems==self.n_items:

                itemPerSec = processedItems/(time.time()-start_time)

                print("Similarity column {} ( {:2.0f} % ), {:.2f} column/sec, elapsed time {:.2f} min".format(
                    processedItems, processedItems*1.0/self.n_items*100, itemPerSec, (time.time()-start_time) / 60))

                sys.stdout.flush()
                sys.stderr.flush()


            this_item_weights = self.computeItemSimilarities(itemIndex)


            # Apply normalization and shrinkage, ensure denominator != 0
            if self.normalize:
                for innerItemIndex in range(self.n_items):
                    this_item_weights[innerItemIndex] /= self.sumOfSquared[itemIndex] * self.sumOfSquared[innerItemIndex]\
                                                         + self.shrink + 1e-6

            # Apply the specific denominator for Tanimoto
            elif self.tanimoto_coefficient:
                for innerItemIndex in range(self.n_items):
                    this_item_weights[innerItemIndex] /= self.sumOfSquared[itemIndex] + self.sumOfSquared[innerItemIndex] -\
                                                         this_item_weights[innerItemIndex] + self.shrink + 1e-6

            elif self.shrink != 0:
                for innerItemIndex in range(self.n_items):
                    this_item_weights[innerItemIndex] /= self.shrink


            if self.TopK == 0:

                for innerItemIndex in range(self.n_items):
                    self.W_dense[innerItemIndex,itemIndex] = this_item_weights[innerItemIndex]

            else:

                # Sort indices and select TopK
                # Using numpy implies some overhead, unfortunately the plain C qsort function is even slower
                #top_k_idx = np.argsort(this_item_weights) [-self.TopK:]

                # Sorting is done in three steps. Faster then plain np.argsort for higher number of items
                # because we avoid sorting elements we already know we don't care about
                # - Partition the data to extract the set of TopK items, this set is unsorted
                # - Sort only the TopK items, discarding the rest
                # - Get the original item index

                this_item_weights_np = - np.array(this_item_weights)
                #
                # Get the unordered set of topK items
                top_k_partition = np.argpartition(this_item_weights_np, self.TopK-1)[0:self.TopK]
                # Sort only the elements in the partition
                top_k_partition_sorting = np.argsort(this_item_weights_np[top_k_partition])
                # Get original index
                top_k_idx = top_k_partition[top_k_partition_sorting]



                # Incrementally build sparse matrix
                for innerItemIndex in range(len(top_k_idx)):

                    topKItemIndex = top_k_idx[innerItemIndex]

                    values[sparse_data_pointer] = this_item_weights[topKItemIndex]
                    rows[sparse_data_pointer] = topKItemIndex
                    cols[sparse_data_pointer] = itemIndex

                    sparse_data_pointer += 1


        if self.TopK == 0:

            return np.array(self.W_dense)

        else:

            values = np.array(values[0:sparse_data_pointer])
            rows = np.array(rows[0:sparse_data_pointer])
            cols = np.array(cols[0:sparse_data_pointer])

            W_sparse = sps.csr_matrix((values, (rows, cols)),
                                    shape=(self.n_items, self.n_items),
                                    dtype=np.float32)

            return W_sparse

