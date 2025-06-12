import tensorflow as tf

def weighted_binary_crossentropy(pos_weight):
    """
    Function for giving more weight to the positive class (where the notes are being played)
    """
    def loss(y_true, y_pred):
        y_pred = tf.clip_by_value(y_pred, 1e-7, 1.0 - 1e-7)
        loss_pos = -pos_weight * y_true * tf.math.log(y_pred)
        loss_neg = -(1 - y_true) * tf.math.log(1 - y_pred)

        loss = loss_pos + loss_neg

        return tf.reduce_mean(loss)

    return loss


def focal_loss(gamma=2.0, alpha=0.25):
    def loss_fn(y_true, y_pred):
        y_pred = tf.clip_by_value(y_pred, 1e-7, 1 - 1e-7)

        bce = -y_true * tf.math.log(y_pred) - (1 - y_true) * tf.math.log(1 - y_pred)

        p_t = (y_true * y_pred) + ((1 - y_true) * (1 - y_pred))
        alpha_factor = y_true * alpha + (1 - y_true) * (1 - alpha)
        modulating_factor = tf.pow(1.0 - p_t, gamma)

        loss = alpha_factor * modulating_factor * bce

        return tf.reduce_mean(loss)

    return loss_fn


class F1Score(tf.keras.metrics.Metric):
    def __init__(self, name='f1_score', threshold=0.3, **kwargs):
        super(F1Score, self).__init__(name=name, **kwargs)
        self.threshold = threshold
        self.precision = tf.keras.metrics.Precision(thresholds=threshold)
        self.recall = tf.keras.metrics.Recall(thresholds=threshold)

    def update_state(self, y_true, y_pred, sample_weight=None):
        self.precision.update_state(y_true, y_pred, sample_weight)
        self.recall.update_state(y_true, y_pred, sample_weight)

    def result(self):
        p = self.precision.result()
        r = self.recall.result()
        return tf.math.divide_no_nan(2 * p * r, p + r)

    def reset_states(self):
        self.precision.reset_states()
        self.recall.reset_states()