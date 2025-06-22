import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import '../config/app_theme.dart';
import '../services/api_service.dart';
import '../services/platform_service.dart';
import '../models/transcription_result.dart';

class SheetMusicViewer extends StatefulWidget {
  final SheetMusic? sheetMusic;
  final String title;
  final ApiService apiService;

  const SheetMusicViewer({
    Key? key,
    required this.sheetMusic,
    required this.title,
    required this.apiService,
  }) : super(key: key);

  @override
  _SheetMusicViewerState createState() => _SheetMusicViewerState();
}

class _SheetMusicViewerState extends State<SheetMusicViewer>
    with SingleTickerProviderStateMixin {
  final PdfViewerController _pdfViewerController = PdfViewerController();
  final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();
  
  bool _isLoading = false;
  bool _isLoaded = false;
  bool _hasError = false;
  Uint8List? _pdfBytes;
  PlatformFile? _downloadedFile;
  String _errorMessage = '';
  
  late AnimationController _fabAnimationController;
  late Animation<double> _fabAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _loadPdf();
  }

  void _setupAnimations() {
    _fabAnimationController = AnimationController(
      duration: Duration(milliseconds: 300),
      vsync: this,
    );
    _fabAnimation = CurvedAnimation(
      parent: _fabAnimationController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _fabAnimationController.dispose();
    super.dispose();
  }

  Future<void> _loadPdf() async {
    if (widget.sheetMusic == null) {
      setState(() {
        _hasError = true;
        _errorMessage = 'No sheet music available for this transcription';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      print('📄 Loading sheet music: ${widget.sheetMusic!.fileUrl}');
      
      if (PlatformService.isWeb) {
        await _loadPdfForWeb();
      } else {
        await _loadPdfForMobile();
      }
      
    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = 'Failed to load sheet music: $e';
      });
      print('❌ Error loading sheet music: $e');
    }
  }

  /// Load PDF for web - FIXED VERSION
  Future<void> _loadPdfForWeb() async {
    try {
      print('🌐 Loading PDF for web...');
      
      _pdfBytes = await _downloadPdfBytesFixed(widget.sheetMusic!.fileUrl);
      
      if (_pdfBytes != null && _pdfBytes!.isNotEmpty) {
        print('✅ PDF bytes ready: ${_pdfBytes!.length} bytes');
        
        // Validate PDF more thoroughly
        if (await _validatePdfBytes(_pdfBytes!)) {
          setState(() {
            _isLoaded = true;
            _isLoading = false;
          });
          
          _fabAnimationController.forward();
          print('✅ PDF ready for SyncFusion viewer');
        } else {
          throw Exception('PDF validation failed - corrupted or invalid format');
        }
      } else {
        throw Exception('No PDF data received');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = 'Web PDF loading error: $e';
      });
    }
  }

  /// Download PDF bytes - FIXED (no unsafe headers)
  Future<Uint8List?> _downloadPdfBytesFixed(String fileUrl) async {
    try {
      final dio = Dio();
      
      // Build URL properly
      String completeUrl;
      if (fileUrl.startsWith('http')) {
        completeUrl = fileUrl;
      } else {
        final baseUrl = widget.apiService.baseUrlPublic;
        completeUrl = baseUrl.endsWith('/') 
            ? '$baseUrl${fileUrl.startsWith('/') ? fileUrl.substring(1) : fileUrl}'
            : '$baseUrl${fileUrl.startsWith('/') ? fileUrl : '/$fileUrl'}';
      }
      
      print('📥 Downloading PDF from: $completeUrl');
      
      final response = await dio.get(
        completeUrl,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(minutes: 3),
          // REMOVED User-Agent header - browsers block this
          headers: {
            'Accept': 'application/pdf,*/*',
            'Cache-Control': 'no-cache',
          },
        ),
      );

      if (response.statusCode == 200) {
        final bytes = Uint8List.fromList(response.data);
        print('✅ Downloaded PDF: ${bytes.length} bytes');
        return bytes;
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.statusMessage}');
      }
    } catch (e) {
      print('❌ Error downloading PDF: $e');
      rethrow;
    }
  }

  /// Validate PDF bytes more thoroughly
  Future<bool> _validatePdfBytes(Uint8List bytes) async {
    try {
      if (bytes.length < 1024) {
        print('❌ PDF too small: ${bytes.length} bytes');
        return false;
      }
      
      // Check PDF header
      final header = String.fromCharCodes(bytes.take(8));
      if (!header.startsWith('%PDF')) {
        print('❌ Invalid PDF header: $header');
        return false;
      }
      
      // Check for PDF trailer
      final endBytes = bytes.skip(bytes.length - 1024).toList();
      final endString = String.fromCharCodes(endBytes);
      
      if (!endString.contains('%%EOF') && !endString.contains('xref')) {
        print('⚠️ PDF might be incomplete, but proceeding...');
      }
      
      // Additional check - look for essential PDF elements
      final pdfString = String.fromCharCodes(bytes.take(2048));
      final hasEssentials = pdfString.contains('/Type') || 
                           pdfString.contains('obj') || 
                           pdfString.contains('stream');
      
      if (!hasEssentials) {
        print('❌ PDF lacks essential elements');
        return false;
      }
      
      print('✅ PDF validation passed');
      return true;
      
    } catch (e) {
      print('❌ PDF validation error: $e');
      return false;
    }
  }

  /// Load PDF for mobile
  Future<void> _loadPdfForMobile() async {
    try {
      final fileName = '${widget.title.replaceAll(' ', '_')}_sheet.pdf';
      
      final downloadedFile = await widget.apiService.downloadSheetMusic(
        widget.sheetMusic!.fileUrl,
        fileName,
      );

      if (downloadedFile != null && !downloadedFile.isWebDownload) {
        setState(() {
          _downloadedFile = downloadedFile;
          _isLoaded = true;
          _isLoading = false;
        });
        
        _fabAnimationController.forward();
        print('✅ PDF downloaded for mobile: ${downloadedFile.path}');
      } else {
        throw Exception('Mobile download failed');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = 'Mobile PDF loading error: $e';
      });
    }
  }

  Future<void> _downloadSheetMusic() async {
    try {
      HapticFeedback.lightImpact();
      
      if (PlatformService.isWeb && _pdfBytes != null) {
        final fileName = '${widget.title.replaceAll(' ', '_')}_sheet.pdf';
        final result = await PlatformService.downloadFile(
          fileBytes: _pdfBytes!,
          fileName: fileName,
          mimeType: 'application/pdf',
        );
        
        if (result != null && result.isWebDownload) {
          _showMessage(result.downloadMessage!, isError: false);
        }
      } else if (_downloadedFile != null) {
        _showMessage('Sheet music is saved to: ${_downloadedFile!.path}', isError: false);
      }
    } catch (e) {
      _showMessage('Failed to download sheet music: $e', isError: true);
    }
  }

  void _showMessage(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
  }

  void _zoomIn() {
    HapticFeedback.selectionClick();
    _pdfViewerController.zoomLevel = _pdfViewerController.zoomLevel * 1.25;
  }

  void _zoomOut() {
    HapticFeedback.selectionClick();
    _pdfViewerController.zoomLevel = _pdfViewerController.zoomLevel * 0.8;
  }

  void _resetZoom() {
    HapticFeedback.mediumImpact();
    _pdfViewerController.zoomLevel = 1.0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppTheme.backgroundColor,
              Color(0xFFE8F4F2),
            ],
          ),
        ),
        child: _buildContent(),
      ),
      floatingActionButton: _buildFloatingActionButtons(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return _buildLoadingState();
    }
    
    if (_hasError) {
      return _buildErrorState();
    }
    
    if (_isLoaded) {
      return _buildPdfViewer();
    }
    
    return _buildEmptyState();
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
            ),
          ),
          SizedBox(height: 24),
          Text(
            'Loading Your Sheet Music...',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textColor,
            ),
          ),
          SizedBox(height: 8),
          Text(
            PlatformService.isWeb 
                ? 'Downloading and validating PDF'
                : 'Downloading and processing PDF',
            style: TextStyle(
              color: AppTheme.textColor.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline,
                size: 50,
                color: Colors.red[400],
              ),
            ),
            SizedBox(height: 24),
            Text(
              'Sheet Music Unavailable',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.textColor,
              ),
            ),
            SizedBox(height: 12),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textColor.withOpacity(0.7),
                fontSize: 16,
              ),
            ),
            SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadPdf,
              icon: Icon(Icons.refresh),
              label: Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.picture_as_pdf,
            size: 80,
            color: AppTheme.textColor.withOpacity(0.5),
          ),
          SizedBox(height: 16),
          Text(
            'No Sheet Music Available',
            style: TextStyle(
              fontSize: 18,
              color: AppTheme.textColor.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPdfViewer() {
    return Stack(
      children: [
        Container(
          margin: EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _buildPdfViewerWidget(),
          ),
        ),
        
        // Zoom controls
        Positioned(
          top: 16,
          right: 16,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: _zoomOut,
                  icon: Icon(Icons.zoom_out, color: AppTheme.textColor),
                  tooltip: 'Zoom Out',
                ),
                IconButton(
                  onPressed: _resetZoom,
                  icon: Icon(Icons.center_focus_strong, color: AppTheme.textColor),
                  tooltip: 'Reset Zoom',
                ),
                IconButton(
                  onPressed: _zoomIn,
                  icon: Icon(Icons.zoom_in, color: AppTheme.textColor),
                  tooltip: 'Zoom In',
                ),
              ],
            ),
          ),
        ),
        
        // Status indicator
        Positioned(
          top: 16,
          left: 16,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.9),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.picture_as_pdf, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text(
                  'Sheet Music Ready',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPdfViewerWidget() {
    if (PlatformService.isWeb && _pdfBytes != null) {
      print('🔧 Rendering PDF with SyncFusion: ${_pdfBytes!.length} bytes');
      return SfPdfViewer.memory(
        _pdfBytes!,
        key: _pdfViewerKey,
        controller: _pdfViewerController,
        enableDoubleTapZooming: true,
        enableTextSelection: false,
        canShowScrollHead: true,
        canShowScrollStatus: true,
        pageLayoutMode: PdfPageLayoutMode.single,
        scrollDirection: PdfScrollDirection.vertical,
        onDocumentLoaded: (details) {
          print('📄 ✅ PDF successfully loaded with ${details.document.pages.count} pages');
        },
        onDocumentLoadFailed: (details) {
          print('❌ PDF load failed in SyncFusion: ${details.error} - ${details.description}');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            setState(() {
              _hasError = true;
              _errorMessage = 'PDF display error: ${details.description}';
            });
          });
        },
        onZoomLevelChanged: (details) {
          print('🔍 Zoom: ${details.newZoomLevel}');
        },
      );
    } else if (_downloadedFile != null && !_downloadedFile!.isWebDownload) {
      return SfPdfViewer.file(
        File(_downloadedFile!.path),
        key: _pdfViewerKey,
        controller: _pdfViewerController,
        enableDoubleTapZooming: true,
        enableTextSelection: false,
        canShowScrollHead: true,
        canShowScrollStatus: true,
        pageLayoutMode: PdfPageLayoutMode.single,
        scrollDirection: PdfScrollDirection.vertical,
        onDocumentLoaded: (details) {
          print('📄 PDF loaded with ${details.document.pages.count} pages');
        },
        onZoomLevelChanged: (details) {
          print('🔍 Zoom: ${details.newZoomLevel}');
        },
      );
    } else {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error, color: Colors.red, size: 48),
            SizedBox(height: 16),
            Text(
              'PDF data not available',
              style: TextStyle(color: AppTheme.textColor),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildFloatingActionButtons() {
    if (!_isLoaded) {
      return SizedBox.shrink();
    }

    return ScaleTransition(
      scale: _fabAnimation,
      child: FloatingActionButton.extended(
        onPressed: _downloadSheetMusic,
        backgroundColor: AppTheme.accentColor,
        foregroundColor: Colors.white,
        elevation: 8,
        icon: Icon(PlatformService.isWeb ? Icons.download : Icons.check),
        label: Text(
          // PlatformService.isWeb ? 'Download' : 'Downloaded',
          'Download',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        heroTag: "download_sheet_music",
      ),
    );
  }
}

// import 'dart:io';
// import 'package:flutter/material.dart';
// import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
// import 'package:share_plus/share_plus.dart';
// import 'package:flutter/services.dart';
// import '../config/app_theme.dart';
// import '../services/api_service.dart';
// import '../models/transcription_result.dart';

// class SheetMusicViewer extends StatefulWidget {
//   final SheetMusic? sheetMusic;
//   final String title;
//   final ApiService apiService;

//   const SheetMusicViewer({
//     Key? key,
//     required this.sheetMusic,
//     required this.title,
//     required this.apiService,
//   }) : super(key: key);

//   @override
//   _SheetMusicViewerState createState() => _SheetMusicViewerState();
// }

// class _SheetMusicViewerState extends State<SheetMusicViewer>
//     with SingleTickerProviderStateMixin {
//   final PdfViewerController _pdfViewerController = PdfViewerController();
//   final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();
  
//   bool _isDownloading = false;
//   bool _isLoaded = false;
//   bool _hasError = false;
//   File? _pdfFile;
//   String _errorMessage = '';
  
//   late AnimationController _fabAnimationController;
//   late Animation<double> _fabAnimation;

//   @override
//   void initState() {
//     super.initState();
//     _setupAnimations();
//     _downloadAndLoadPdf();
//   }

//   void _setupAnimations() {
//     _fabAnimationController = AnimationController(
//       duration: Duration(milliseconds: 300),
//       vsync: this,
//     );
//     _fabAnimation = CurvedAnimation(
//       parent: _fabAnimationController,
//       curve: Curves.easeInOut,
//     );
//   }

//   @override
//   void dispose() {
//     _fabAnimationController.dispose();
//     super.dispose();
//   }

//   Future<void> _downloadAndLoadPdf() async {
//     if (widget.sheetMusic == null) {
//       setState(() {
//         _hasError = true;
//         _errorMessage = 'No sheet music available for this transcription';
//       });
//       return;
//     }

//     setState(() {
//       _isDownloading = true;
//       _hasError = false;
//     });

//     try {
//       final fileName = '${widget.title.replaceAll(' ', '_')}_sheet.${widget.sheetMusic!.format}';
      
//       print('📄 Downloading sheet music: ${widget.sheetMusic!.fileUrl}');
      
//       final file = await widget.apiService.downloadSheetMusic(
//         widget.sheetMusic!.fileUrl,
//         fileName,
//       );

//       if (file != null && await file.exists()) {
//         setState(() {
//           _pdfFile = file;
//           _isLoaded = true;
//           _isDownloading = false;
//         });
        
//         _fabAnimationController.forward();
        
//         print('✅ Sheet music loaded successfully: ${file.path}');
//       } else {
//         throw Exception('Downloaded file does not exist');
//       }
//     } catch (e) {
//       setState(() {
//         _isDownloading = false;
//         _hasError = true;
//         _errorMessage = 'Failed to download sheet music: $e';
//       });
//       print('❌ Error loading sheet music: $e');
//     }
//   }

//   Future<void> _shareSheetMusic() async {
//     if (_pdfFile == null) return;

//     try {
//       HapticFeedback.lightImpact();
//       await Share.shareXFiles(
//         [XFile(_pdfFile!.path)],
//         text: 'My piano sheet music - ${widget.title}',
//       );
//     } catch (e) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Text('Failed to share sheet music: $e'),
//           backgroundColor: Colors.red,
//         ),
//       );
//     }
//   }

//   void _zoomIn() {
//     HapticFeedback.selectionClick();
//     _pdfViewerController.zoomLevel = _pdfViewerController.zoomLevel * 1.25;
//   }

//   void _zoomOut() {
//     HapticFeedback.selectionClick();
//     _pdfViewerController.zoomLevel = _pdfViewerController.zoomLevel * 0.8;
//   }

//   void _resetZoom() {
//     HapticFeedback.mediumImpact();
//     _pdfViewerController.zoomLevel = 1.0;
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: Container(
//         decoration: BoxDecoration(
//           gradient: LinearGradient(
//             begin: Alignment.topCenter,
//             end: Alignment.bottomCenter,
//             colors: [
//               AppTheme.backgroundColor,
//               Color(0xFFE8F4F2),
//             ],
//           ),
//         ),
//         child: _buildContent(),
//       ),
//       floatingActionButton: _buildFloatingActionButtons(),
//       floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
//     );
//   }

//   Widget _buildContent() {
//     if (_isDownloading) {
//       return _buildLoadingState();
//     }
    
//     if (_hasError) {
//       return _buildErrorState();
//     }
    
//     if (_isLoaded && _pdfFile != null) {
//       return _buildPdfViewer();
//     }
    
//     return _buildEmptyState();
//   }

//   Widget _buildLoadingState() {
//     return Center(
//       child: Column(
//         mainAxisAlignment: MainAxisAlignment.center,
//         children: [
//           Container(
//             width: 80,
//             height: 80,
//             decoration: BoxDecoration(
//               color: Colors.white,
//               shape: BoxShape.circle,
//               boxShadow: [
//                 BoxShadow(
//                   color: AppTheme.primaryColor.withOpacity(0.3),
//                   blurRadius: 20,
//                   spreadRadius: 5,
//                 ),
//               ],
//             ),
//             child: CircularProgressIndicator(
//               strokeWidth: 3,
//               valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
//             ),
//           ),
//           SizedBox(height: 24),
//           Text(
//             'Preparing Your Sheet Music...',
//             style: TextStyle(
//               fontSize: 18,
//               fontWeight: FontWeight.w600,
//               color: AppTheme.textColor,
//             ),
//           ),
//           SizedBox(height: 8),
//           Text(
//             'Downloading and processing PDF',
//             style: TextStyle(
//               color: AppTheme.textColor.withOpacity(0.7),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildErrorState() {
//     return Center(
//       child: Padding(
//         padding: EdgeInsets.all(32),
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             Container(
//               width: 100,
//               height: 100,
//               decoration: BoxDecoration(
//                 color: Colors.red.withOpacity(0.1),
//                 shape: BoxShape.circle,
//               ),
//               child: Icon(
//                 Icons.error_outline,
//                 size: 50,
//                 color: Colors.red[400],
//               ),
//             ),
//             SizedBox(height: 24),
//             Text(
//               'Sheet Music Unavailable',
//               style: TextStyle(
//                 fontSize: 20,
//                 fontWeight: FontWeight.bold,
//                 color: AppTheme.textColor,
//               ),
//             ),
//             SizedBox(height: 12),
//             Text(
//               _errorMessage,
//               textAlign: TextAlign.center,
//               style: TextStyle(
//                 color: AppTheme.textColor.withOpacity(0.7),
//                 fontSize: 16,
//               ),
//             ),
//             SizedBox(height: 24),
//             ElevatedButton.icon(
//               onPressed: _downloadAndLoadPdf,
//               icon: Icon(Icons.refresh),
//               label: Text('Try Again'),
//               style: ElevatedButton.styleFrom(
//                 backgroundColor: AppTheme.primaryColor,
//                 foregroundColor: Colors.white,
//                 padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
//                 shape: RoundedRectangleBorder(
//                   borderRadius: BorderRadius.circular(25),
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildEmptyState() {
//     return Center(
//       child: Column(
//         mainAxisAlignment: MainAxisAlignment.center,
//         children: [
//           Icon(
//             Icons.picture_as_pdf,
//             size: 80,
//             color: AppTheme.textColor.withOpacity(0.5),
//           ),
//           SizedBox(height: 16),
//           Text(
//             'No Sheet Music Available',
//             style: TextStyle(
//               fontSize: 18,
//               color: AppTheme.textColor.withOpacity(0.7),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildPdfViewer() {
//     return Stack(
//       children: [
//         Container(
//           margin: EdgeInsets.all(8),
//           decoration: BoxDecoration(
//             borderRadius: BorderRadius.circular(12),
//             boxShadow: [
//               BoxShadow(
//                 color: Colors.black.withOpacity(0.1),
//                 blurRadius: 10,
//                 spreadRadius: 2,
//               ),
//             ],
//           ),
//           child: ClipRRect(
//             borderRadius: BorderRadius.circular(12),
//             child: SfPdfViewer.file(
//               _pdfFile!,
//               key: _pdfViewerKey,
//               controller: _pdfViewerController,
//               enableDoubleTapZooming: true,
//               enableTextSelection: false,
//               canShowScrollHead: true,
//               canShowScrollStatus: true,
//               onDocumentLoaded: (PdfDocumentLoadedDetails details) {
//                 print('📄 PDF loaded with ${details.document.pages.count} pages');
//               },
//               onZoomLevelChanged: (PdfZoomDetails details) {
//                 print('🔍 Zoom level: ${details.newZoomLevel}');
//               },
//               scrollDirection: PdfScrollDirection.vertical,
//               pageLayoutMode: PdfPageLayoutMode.single,
//             ),
//           ),
//         ),
        
//         Positioned(
//           top: 16,
//           right: 16,
//           child: Container(
//             decoration: BoxDecoration(
//               color: Colors.white.withOpacity(0.9),
//               borderRadius: BorderRadius.circular(25),
//               boxShadow: [
//                 BoxShadow(
//                   color: Colors.black.withOpacity(0.1),
//                   blurRadius: 8,
//                   spreadRadius: 1,
//                 ),
//               ],
//             ),
//             child: Row(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 IconButton(
//                   onPressed: _zoomOut,
//                   icon: Icon(Icons.zoom_out, color: AppTheme.textColor),
//                   tooltip: 'Zoom Out',
//                 ),
//                 IconButton(
//                   onPressed: _resetZoom,
//                   icon: Icon(Icons.center_focus_strong, color: AppTheme.textColor),
//                   tooltip: 'Reset Zoom',
//                 ),
//                 IconButton(
//                   onPressed: _zoomIn,
//                   icon: Icon(Icons.zoom_in, color: AppTheme.textColor),
//                   tooltip: 'Zoom In',
//                 ),
//               ],
//             ),
//           ),
//         ),
        
//         Positioned(
//           top: 16,
//           left: 16,
//           child: Container(
//             padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
//             decoration: BoxDecoration(
//               color: AppTheme.primaryColor.withOpacity(0.9),
//               borderRadius: BorderRadius.circular(20),
//               boxShadow: [
//                 BoxShadow(
//                   color: Colors.black.withOpacity(0.1),
//                   blurRadius: 8,
//                   spreadRadius: 1,
//                 ),
//               ],
//             ),
//             child: Row(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 Icon(
//                   Icons.picture_as_pdf,
//                   color: Colors.white,
//                   size: 18,
//                 ),
//                 SizedBox(width: 8),
//                 Text(
//                   'Sheet Music',
//                   style: TextStyle(
//                     color: Colors.white,
//                     fontWeight: FontWeight.w600,
//                     fontSize: 14,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _buildFloatingActionButtons() {
//     if (!_isLoaded || _pdfFile == null) {
//       return SizedBox.shrink();
//     }

//     return ScaleTransition(
//       scale: _fabAnimation,
//       child: FloatingActionButton.extended(
//         onPressed: _shareSheetMusic,
//         backgroundColor: AppTheme.accentColor,
//         foregroundColor: Colors.white,
//         elevation: 8,
//         icon: Icon(Icons.file_download),
//         label: Text(
//           'Download',
//           style: TextStyle(fontWeight: FontWeight.w600),
//         ),
//         heroTag: "download_sheet_music",
//       ),
//     );
//   }
// }