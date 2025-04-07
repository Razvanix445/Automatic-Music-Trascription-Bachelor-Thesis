import tensorflow as tf
from tensorflow.keras.layers import (Input, Conv2D, BatchNormalization, Activation,
                                     MaxPooling2D, Reshape, Dropout, Bidirectional,
                                     LSTM, Dense, Concatenate, TimeDistributed,
                                     Attention, LayerNormalization, Add, Lambda)


def acoustic_feature_extractor(inputs, training=True):
    """
    Enhanced acoustic feature extractor with residual connections.
    """
    # Initial convolution
    x = Conv2D(48, kernel_size=(3, 3), padding='same', name='conv1')(inputs)
    x = BatchNormalization(name='bn1')(x, training=training)
    x = Activation('relu')(x)
    x = MaxPooling2D(pool_size=(1, 2), name='pool1')(x)

    # Block 2 with residual connection
    shortcut = x
    x = Conv2D(48, kernel_size=(3, 3), padding='same', name='conv2a')(x)
    x = BatchNormalization(name='bn2a')(x, training=training)
    x = Activation('relu')(x)
    x = Conv2D(48, kernel_size=(3, 3), padding='same', name='conv2b')(x)
    x = BatchNormalization(name='bn2b')(x, training=training)
    x = Add()([x, shortcut])  # Add residual connection
    x = Activation('relu')(x)
    x = MaxPooling2D(pool_size=(1, 2), name='pool2')(x)

    # Block 3 with residual connection
    shortcut = Conv2D(96, kernel_size=(1, 1), padding='same')(x)
    shortcut = BatchNormalization()(shortcut, training=training)

    x = Conv2D(96, kernel_size=(3, 3), padding='same', name='conv3a')(x)
    x = BatchNormalization(name='bn3a')(x, training=training)
    x = Activation('relu')(x)
    x = Conv2D(96, kernel_size=(3, 3), padding='same', name='conv3b')(x)
    x = BatchNormalization(name='bn3b')(x, training=training)
    x = Add()([x, shortcut])
    x = Activation('relu')(x)
    x = MaxPooling2D(pool_size=(1, 2), name='pool3')(x)

    return x


def vertical_dependencies_layer(x, units=88, training=True, name_prefix=""):
    """
    Process vertical (harmonic) dependencies across piano notes.
    """
    # Get input shape information
    input_shape = tf.keras.backend.int_shape(x)
    time_steps, features = input_shape[1], input_shape[2]

    # Calculate features per note, divisible by 88
    features_per_note = features // 88
    if features % 88 != 0:
        # Add padding to make features divisible by 88
        padding_size = 88 - (features % 88)
        padding = tf.keras.layers.Dense(padding_size, name=f"{name_prefix}_padding_for_chord")(x)
        x = Concatenate(axis=-1, name=f"{name_prefix}_concat_padding")([x, padding])
        features_per_note = (features + padding_size) // 88

    x_reshaped = Reshape((time_steps, 88, features_per_note), name=f"{name_prefix}_reshape_to_chord")(x)

    # Apply convolution across pitch dimension
    x_chord = Conv2D(filters=32, kernel_size=(1, 12), padding='same', name=f"{name_prefix}_chord_conv")(x_reshaped)
    x_chord = BatchNormalization(name=f"{name_prefix}_chord_bn")(x_chord, training=training)
    x_chord = Activation('relu', name=f"{name_prefix}_chord_relu")(x_chord)

    x_chord = Reshape((time_steps, 88 * 32), name=f"{name_prefix}_reshape_from_chord")(x_chord)

    x_out = Dense(units, name=f"{name_prefix}_chord_projection")(x_chord)

    return x_out


def lstm_with_attention(x, units, return_sequences=True, training=True, name=None):
    """
    LSTM layer with self-attention mechanism.
    """
    # Bidirectional LSTM
    lstm_out = Bidirectional(LSTM(units, return_sequences=return_sequences), name=name)(x)

    # Self-attention mechanism
    attention_out = Attention()([lstm_out, lstm_out])

    # Combined LSTM output with attention
    combined = Add()([lstm_out, attention_out])

    combined = Dropout(0.25)(combined, training=training)

    return combined


def onset_subnetwork(reshaped_features, training=True):
    """
    Enhanced onset subnetwork with attention mechanisms
    """
    x = Dropout(0.5, name='onset_dropout1')(reshaped_features, training=training)

    # First LSTM with attention
    x = lstm_with_attention(x, 256, name='onset_lstm1', training=training)

    # Second LSTM with attention
    x = lstm_with_attention(x, 256, name='onset_lstm2', training=training)

    # Model vertical dependencies across piano notes
    x_vertical = vertical_dependencies_layer(x, units=88, training=training, name_prefix="onset")

    # Final prediction
    onset_predictions = Activation('sigmoid', name='onset_dense')(x_vertical)

    return onset_predictions, x


def frame_subnetwork(reshaped_features, onset_predictions, training=True):
    """
    Enhanced frame subnetwork
    """
    # Concatenate features with onset predictions
    x = Concatenate(axis=-1, name='frame_concat')([reshaped_features, onset_predictions])

    x = Dropout(0.25, name='frame_dropout1')(x, training=training)

    # First LSTM with attention
    x = lstm_with_attention(x, 256, name='frame_lstm1', training=training)

    # Second LSTM with attention
    x = lstm_with_attention(x, 256, name='frame_lstm2', training=training)

    # Model vertical dependencies across piano notes
    x_vertical = vertical_dependencies_layer(x, units=88, training=training, name_prefix="frame")

    # Final prediction
    frame_predictions = Activation('sigmoid', name='frame_dense')(x_vertical)

    return frame_predictions, x


def offset_subnetwork(reshaped_features, onset_predictions, frame_predictions, training=True):
    """
    Enhanced offset subnetwork that uses both onset and frame information
    """
    # Concatenate features with onset and frame predictions
    x = Concatenate(axis=-1, name='offset_concat')(
        [reshaped_features, onset_predictions, frame_predictions])

    x = Dropout(0.5, name='offset_dropout1')(x, training=training)

    # First LSTM with attention
    x = lstm_with_attention(x, 256, name='offset_lstm1', training=training)

    # Second LSTM with attention
    x = lstm_with_attention(x, 256, name='offset_lstm2', training=training)

    # Model vertical dependencies across piano notes
    x_vertical = vertical_dependencies_layer(x, units=88, training=training, name_prefix="offset")

    # Final prediction
    offset_predictions = Activation('sigmoid', name='offset_dense')(x_vertical)

    return offset_predictions, x


def velocity_subnetwork(reshaped_features, onset_predictions, frame_predictions, training=True):
    """
    Enhanced velocity subnetwork
    """
    # Concatenate features with onset and frame predictions
    x = Concatenate(axis=-1, name='velocity_concat')(
        [reshaped_features, onset_predictions, frame_predictions])

    x = Dropout(0.25, name='velocity_dropout1')(x, training=training)

    # First LSTM with attention
    x = lstm_with_attention(x, 256, name='velocity_lstm1', training=training)

    # Second LSTM with attention
    x = lstm_with_attention(x, 256, name='velocity_lstm2', training=training)

    # Model vertical dependencies across piano notes
    x_vertical = vertical_dependencies_layer(x, units=88, training=training, name_prefix="velocity")

    # Final prediction
    velocity_predictions = Activation('sigmoid', name='velocity_dense')(x_vertical)

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

    def dynamic_reshape(x):
        input_shape = tf.shape(x)
        batch_size = input_shape[0]
        time_steps = input_shape[1]
        freq_steps = input_shape[2]
        channels = input_shape[3]
        return tf.reshape(x, [batch_size, time_steps, freq_steps * channels])

    reshaped_features = Lambda(dynamic_reshape, name='reshape_features')(conv_out)

    print("=============================== Reshaped features =======================: ", reshaped_features)

    onset_predictions, onset_features = onset_subnetwork(reshaped_features, training=training)
    frame_predictions, frame_features = frame_subnetwork(reshaped_features, onset_predictions, training=training)
    offset_predictions, offset_features = offset_subnetwork(reshaped_features, onset_predictions, frame_predictions, training=training)
    velocity_predictions, velocity_features = velocity_subnetwork(reshaped_features, onset_predictions, frame_predictions, training=training)

    model = tf.keras.Model(
          inputs=inputs,
          outputs=[onset_predictions, frame_predictions, offset_predictions, velocity_predictions],
          name='PianoTranscriptionModel')
    return model


# if __name__ == '__main__':
    # input_shape = (938, 128, 1)
    # model = build_model(input_shape, training=True)
    # model.summary()
