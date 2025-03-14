import tensorflow as tf
from tensorflow.keras.layers import (Input, Conv2D, BatchNormalization, Activation, MaxPooling2D,
                                     Reshape, Dropout, Bidirectional, LSTM, Dense, Concatenate)


def acoustic_feature_extractor(inputs, training=True):
    """
    Acoustic feature extractor using 3 convolutional blocks.
    """
    # Block 1
    x = Conv2D(48, kernel_size=(3, 3), padding='same', name='conv1')(inputs)
    x = BatchNormalization(name='bn1')(x, training=training)
    x = Activation('relu')(x)
    x = MaxPooling2D(pool_size=(2, 2), name='pool1')(x)

    # Block 2
    x = Conv2D(48, kernel_size=(3, 3), padding='same', name='conv2')(x)
    x = BatchNormalization(name='bn2')(x, training=training)
    x = Activation('relu')(x)
    x = MaxPooling2D(pool_size=(2, 2), name='pool2')(x)

    # Block 3
    x = Conv2D(96, kernel_size=(3, 3), padding='same', name='conv3')(x)
    x = BatchNormalization(name='bn3')(x, training=training)
    x = Activation('relu')(x)
    x = MaxPooling2D(pool_size=(2, 2), name='pool3')(x)

    return x


def onset_subnetwork(reshaped_features, training=True):
    """
    Onset subnetwork
    """
    x = Dropout(0.25, name='onset_dropout1')(reshaped_features, training=training)
    x = Bidirectional(LSTM(256, return_sequences=True), name='onset_lstm1')(x)
    x = Dropout(0.25, name='onset_dropout2')(x, training=training)
    x = Bidirectional(LSTM(256, return_sequences=True), name='onset_lstm2')(x)
    x = Dropout(0.25, name='onset_dropout3')(x, training=training)
    onset_predictions = Dense(88, activation='sigmoid', name='onset_dense')(x)
    return onset_predictions, x


def frame_subnetwork(reshaped_features, onset_predictions, training=True):
    """
    Frame subnetwork
    """
    x = Concatenate(axis=-1, name='frame_concat')([reshaped_features, onset_predictions])
    x = Dropout(0.25, name='frame_dropout1')(x, training=training)
    x = Bidirectional(LSTM(256, return_sequences=True), name='frame_lstm1')(x)
    x = Dropout(0.25, name='frame_dropout2')(x, training=training)
    x = Bidirectional(LSTM(256, return_sequences=True), name='frame_lstm2')(x)
    x = Dropout(0.25, name='frame_dropout3')(x, training=training)
    frame_predictions = Dense(88, activation='sigmoid', name='frame_dense')(x)
    return frame_predictions, x


def offset_subnetwork(reshaped_features, onset_predictions, training=True):
    """
    Offset subnetwork
    """
    x = Concatenate(axis=-1, name='offset_concat')([reshaped_features, onset_predictions])
    x = Dropout(0.25, name='offset_dropout1')(x, training=training)
    x = Bidirectional(LSTM(256, return_sequences=True), name='offset_lstm1')(x)
    x = Dropout(0.25, name='offset_dropout2')(x, training=training)
    x = Bidirectional(LSTM(256, return_sequences=True), name='offset_lstm2')(x)
    x = Dropout(0.25, name='offset_dropout3')(x, training=training)
    offset_predictions = Dense(88, activation='sigmoid', name='offset_dense')(x)
    return offset_predictions, x


def velocity_subnetwork(reshaped_features, onset_predictions, training=True):
    """
    Velocity subnetwork
    """
    x = Concatenate(axis=-1, name='velocity_concat')([reshaped_features, onset_predictions])
    x = Dropout(0.25, name='velocity_dropout1')(x, training=training)
    x = Bidirectional(LSTM(256, return_sequences=True), name='velocity_lstm1')(x)
    x = Dropout(0.25, name='velocity_dropout2')(x, training=training)
    x = Bidirectional(LSTM(256, return_sequences=True), name='velocity_lstm2')(x)
    x = Dropout(0.25, name='velocity_dropout3')(x, training=training)
    velocity_predictions = Dense(88, activation='sigmoid', name='velocity_dense')(x)
    return velocity_predictions, x


def build_model(input_shape, training=True):
    """
    Function to build the complete model with:
      - Acoustic feature extraction (3 CNN blocks)
      - Onset subnetwork (2-layer BiLSTM)
      - Frame subnetwork (2-layer BiLSTM, concatenated with onsets)
      - Offset subnetwork (2-layer BiLSTM, concatenated with onsets)
      - Velocity subnetwork (2-layer BiLSTM, concatenated with onsets)
    """
    inputs = Input(shape=input_shape, name='mel_spectrogram')

    conv_out = acoustic_feature_extractor(inputs, training=training)

    conv_shape = tf.keras.backend.int_shape(conv_out)
    time_steps = conv_shape[1]
    feature_dim = conv_shape[2] * conv_shape[3]
    reshaped_features = Reshape((time_steps, feature_dim), name='reshape_features')(conv_out)

    onset_predictions, onset_features = onset_subnetwork(reshaped_features, training=training)

    frame_predictions, frame_features = frame_subnetwork(reshaped_features, onset_predictions, training=training)

    offset_predictions, offset_features = offset_subnetwork(reshaped_features, onset_predictions, training=training)

    velocity_predictions, velocity_features = velocity_subnetwork(reshaped_features, onset_predictions, training=training)

    model = tf.keras.Model(inputs=inputs,
                  outputs=[onset_predictions, frame_predictions, offset_predictions, velocity_predictions],
                  name='PianoTranscriptionModel')
    return model


# if __name__ == '__main__':
    # input_shape = (938, 128, 1)
    # model = build_model(input_shape, training=True)
    # model.summary()
