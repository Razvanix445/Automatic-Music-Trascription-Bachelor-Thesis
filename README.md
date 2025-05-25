# 🎵 Wave2Notes - AI-Powered Music Transcription

[![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev/)
[![TensorFlow](https://img.shields.io/badge/TensorFlow-FF6F00?style=for-the-badge&logo=tensorflow&logoColor=white)](https://tensorflow.org/)
[![Python](https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white)](https://python.org/)
[![Hugging Face](https://img.shields.io/badge/%F0%9F%A4%97%20Hugging%20Face-FFD21E?style=for-the-badge)](https://huggingface.co/)

> 🎓 **Bachelor's Thesis Project** - Automatic Music Transcription using Deep Learning

Transform piano recordings into MIDI files using an Automatic Music Transcription model! Wave2Notes combines advanced deep learning with an intuitive mobile interface to provide real-time music transcription capabilities.

## 🌟 Features

### 🎹 **Core Functionality**
- **🎤 Audio Recording** - Record piano music directly in the app
- **📁 File Upload** - Support for WAV, MP3, M4A, and other audio formats
- **🤖 AI Transcription** - Deep learning-powered note detection
- **🎼 MIDI Export** - Professional MIDI files for music software
- **📊 Detailed Analysis** - Note timing, pitch, and velocity information

### 📱 **Mobile Experience**
- **🎨 Piano Roll Visualization** - Interactive note display
- **▶️ MIDI Playback** - Built-in audio player
- **📤 Share & Export** - Easy file sharing capabilities
- **🔐 User Authentication** - Secure Firebase-based login
- **☁️ Cloud Storage** - AWS S3 integration for recordings

### 🧠 **AI Technology**
- **🏗️ Multi-Task Architecture** - Simultaneous onset, frame, offset, and velocity detection
- **🎯 Piano-Optimized** - Specialized for 88-key piano transcription
- **⚡ Real-Time Processing** - Fast inference with GPU acceleration
- **🎚️ Precision Control** - Configurable detection thresholds

## 🏗️ Architecture

```
┌─────────────────┐    ┌───────────────────┐    ┌─────────────────────┐
│                 │    │                   │    │                     │
│ 📱 Flutter App │───▶│ 🌐 Flask API     │───▶│ 🧠 TensorFlow      │
│                 │    │  (Hugging Face)   │    │  Model              │
│  • Recording    │    │                   │    │                     │
│  • Playback     │    │  • Audio Process  │    │  • CNN Features     │
│  • UI/UX        │    │  • ML Inference   │    │  • BiLSTM+Attention │
│                 │    │  • MIDI Creation  │    │  • Multi-task Heads │
└─────────────────┘    └───────────────────┘    └─────────────────────┘
         │                        │                         │
         │                        │                         │
         ▼                        ▼                         ▼
┌─────────────────┐    ┌───────────────────┐    ┌─────────────────────┐
│                 │    │                   │    │                     │
│  🔥 Firebase    │    │  📦 AWS S3       │    │  🤗 Hugging Face    │
│                 │    │                   │    │                     │
│ • Authentication|    │ • File Storage    │    │  • Model Hosting    │
│ • User Data     │    │ • Recording Backup|    │  • Version Control  │
│                 │    │                   │    │                     │
└─────────────────┘    └───────────────────┘    └─────────────────────┘
```

## 🔬 Technical Specifications

### 🎯 **Machine Learning Model**

| Component | Details |
|-----------|---------|
| **🏗️ Architecture** | Multi-Task CNN + Bidirectional LSTM with Attention |
| **📊 Input** | Mel-spectrogram (229 frequency bins, 32ms resolution) |
| **🎹 Output** | 88-key piano roll (A0 to C8) |
| **🎯 Tasks** | Onset Detection, Frame Detection, Offset Detection, Velocity Estimation |
| **📈 Features** | Residual connections, Self-attention, Vertical dependency modeling |
| **⚖️ Loss Functions** | Weighted Binary Cross-entropy, Focal Loss |
| **📏 Metrics** | F1-Score, Precision, Recall |

### 🔧 **Technical Stack**

#### **🖥️ Backend (Python)**
```yaml
Framework: Flask 3.0.0
ML Library: TensorFlow 2.15.0
Audio Processing: Librosa 0.10.1
MIDI Generation: Mido 1.3.2
Audio Conversion: Pydub 0.25.1
Model Hosting: Hugging Face Hub
API Hosting: Hugging Face Spaces
```

#### **📱 Frontend (Flutter)**
```yaml
Framework: Flutter (Dart)
Authentication: Firebase Auth
Storage: AWS S3
HTTP Client: Dio
Audio Recording: flutter_sound
File Handling: file_picker
UI Components: Material Design
```

#### **☁️ Infrastructure**
```yaml
Model Storage: Hugging Face Hub (~500MB SavedModel)
API Hosting: Hugging Face Spaces (4GB RAM, GPU support)
Authentication: Firebase
File Storage: AWS S3
```

## 🚀 Getting Started

### 📋 **Prerequisites**

- **📱 Flutter SDK** (>=3.0.0)
- **🎯 Dart** (>=3.0.0)
- **🔥 Firebase Account** (for authentication)
- **☁️ AWS Account** (for S3 storage)
- **📱 Android Studio** or **🍎 Xcode** (for mobile development)

## 🔗 **API Integration**

The backend API is hosted on Hugging Face Spaces.

## 📊 **Model Performance**

### **🎯 Evaluation Metrics**
- **🎵 Note Detection Accuracy**: ~50-55%
- **⏱️ Onset Timing Precision**: ±32ms
- **🎹 Piano Range Coverage**: 88 keys (A0-C8)
- **⚡ Processing Speed**: ~10-30 seconds per minute of audio
- **🎚️ Velocity Estimation**: Correlation coefficient ~0.78

### **📈 Training Details**
- **📚 Dataset**: Piano audio recordings with MIDI ground truth
- **🔄 Training Epochs**: 100+ with early stopping
- **📊 Batch Size**: 16
- **🎯 Optimizer**: Adam with learning rate scheduling
- **🏋️ Loss Weighting**: Balanced for onset/frame/offset tasks

## 🧪 **Usage Examples**

### **📱 Mobile App Usage**
1. **🚀 Launch** the Wave2Notes app
2. **🔐 Login** with your Firebase account
3. **🎤 Record** piano music or **📁 upload** an audio file
4. **⏳ Wait** for AI processing (10-30 seconds)
5. **📥 Download** your MIDI file and **👀 view** detected notes in a Synthesia-like format
6. **🎵 Play** back the transcription or **📤 share** results

## 🎓 **Academic Context**

This project was developed as a **Bachelor's Thesis** on:

**"Automatic Music Transcription using Deep Learning Techniques"**

### **🎯 Research Objectives**
- Investigate multi-task learning for music transcription
- Compare CNN vs. RNN architectures for temporal modeling
- Evaluate attention mechanisms in music signal processing
- Develop practical mobile application for real-world usage
