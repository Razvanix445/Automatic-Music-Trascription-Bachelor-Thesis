import os
import tensorflow as tf


class ModelLoader:
    def __init__(self):
        # Model is stored directly in the Space
        self.local_model_path = "models/saved_model"
        self.model = None
        print("ModelLoader initialized - ready for lazy loading")

    def get_model(self):
        """Get model, loading it if necessary (lazy loading)"""
        if self.model is None:
            print("Model not loaded yet - loading now...")
            self.load_model()
        return self.model

    def load_model(self):
        """Load model from local files"""
        try:
            print(f"Loading SavedModel from: {self.local_model_path}")
            
            # Check if model exists
            if not os.path.exists(self.local_model_path):
                raise FileNotFoundError(f"Model not found at: {self.local_model_path}")
            
            # Load the model
            loaded_model = tf.saved_model.load(self.local_model_path)

            # Add predict wrapper
            def predict_wrapper(input_data):
                return loaded_model(input_data)

            loaded_model.predict = predict_wrapper
            self.model = loaded_model
            print("✅ Model loaded successfully from local files")

        except Exception as e:
            print(f"❌ Error loading model: {e}")
            raise

    def is_model_ready(self):
        """Check if model is loaded and ready"""
        return self.model is not None