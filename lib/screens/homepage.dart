import 'dart:io';
import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:flutter_tflite/flutter_tflite.dart';
import 'package:image_picker/image_picker.dart';
import '../constants/constants.dart';
import '../services/api_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image/image.dart' as img; // Importing image package for preprocessing

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<HomePage> {
  final apiService = ApiService();
  File? _selectedImage;
  String diseaseName = '';
  String diseasePrecautions = '';
  bool detecting = false;
  bool precautionLoading = false;
  String modelResult = '';

  @override
  void dispose() {
    super.dispose();
    Tflite.close();
  }

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  Future<void> _loadModel() async {
    await Tflite.loadModel(
      model: "assets/model2_unquant.tflite",
      labels: "assets/labels.txt",
      numThreads: 1,
      isAsset: true,
      useGpuDelegate: false,
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final pickedFile = await ImagePicker().pickImage(source: source, imageQuality: 50);
    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  }

  // Function to preprocess the image
  Future<File> preprocessImage(File image) async {
    // Load the image
    img.Image originalImage = img.decodeImage(image.readAsBytesSync())!;

    // Resize the image
    img.Image resizedImage = img.copyResize(originalImage, width: 224, height: 224);

    // Convert to bytes
    final newFile = File(image.path)..writeAsBytesSync(img.encodeJpg(resizedImage, quality: 100));
    return newFile;
  }

  Future<bool> isLikelyPlantImage(File image) async {
    try {
      // Load the image
      img.Image? originalImage = img.decodeImage(image.readAsBytesSync());
      if (originalImage == null) {
        return false;
      }

      // Resize the image
      img.Image resizedImage = img.copyResize(originalImage, width: 224, height: 224);

      // Check for a dominant green color (heuristic filter for plants)
      int greenPixels = 0;
      int totalPixels = resizedImage.width * resizedImage.height;

      for (int y = 0; y < resizedImage.height; y++) {
        for (int x = 0; x < resizedImage.width; x++) {
          int pixel = resizedImage.getPixel(x, y);
          int r = img.getRed(pixel);
          int g = img.getGreen(pixel);
          int b = img.getBlue(pixel);

          // Heuristic: if the green component is significantly higher than red and blue, it's likely a plant leaf
          if (g > r && g > b && g > 100) {
            greenPixels++;
          }
        }
      }

      // If more than 30% of the image is green, consider it a plant image
      return (greenPixels / totalPixels) > 0.3;
    } catch (error) {
      print("Error in image preprocessing: $error");
      return false;
    }
  }

  Future<void> detectDisease() async {
    if (_selectedImage == null) return;

    setState(() {
      detecting = true;
    });

    try {
      // First, check if the image is likely to be a plant image
      bool isPlant = await isLikelyPlantImage(_selectedImage!);

      if (!isPlant) {
        setState(() {
          modelResult = 'The image does not appear to be a plant. Take a clearer image.';
        });
        return;
      }

      // Preprocess the image if it is a plant
      File preprocessedImage = await preprocessImage(_selectedImage!);

      var result = await Tflite.runModelOnImage(
        path: preprocessedImage.path,
        numResults: 1,
        threshold: 0.7,
      );

      if (result != null && result.isNotEmpty) {
        var confidence = result[0]['confidence']; // Access the confidence value

        print(confidence);

        if (confidence >= 0.8) {
          modelResult = result[0]['label']; // Only consider results with confidence above the threshold
        } else {
          modelResult = "Prediction confidence too low"; // Handle low confidence results
        }
      }
    } catch (error) {
      _showErrorSnackBar(error);
    } finally {
      setState(() {
        detecting = false;
      });
    }
  }


  Future<void> advancedDetect() async {
    setState(() {
      detecting = true;
    });
    try {
      diseaseName = await apiService.sendImageToGPT4Vision(image: _selectedImage!);
    } catch (error) {
      _showErrorSnackBar(error);
    } finally {
      setState(() {
        detecting = false;
      });
    }
  }

  Future<void> showPrecautions() async {
    setState(() {
      precautionLoading = true;
    });
    try {
      if (diseasePrecautions == '') {
        diseasePrecautions = await apiService.sendMessageGPT(diseaseName: diseaseName);
      }
      _showSuccessDialog(diseaseName, diseasePrecautions);
    } catch (error) {
      _showErrorSnackBar(error);
    } finally {
      setState(() {
        precautionLoading = false;
      });
    }
  }

  void _showErrorSnackBar(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error.toString()),
      backgroundColor: Colors.red,
    ));
  }

  void _showSuccessDialog(String title, String content) {
    AwesomeDialog(
      context: context,
      dialogType: DialogType.success,
      animType: AnimType.rightSlide,
      title: title,
      desc: content,
      btnOkText: 'Got it',
      btnOkColor: themeColor,
      btnOkOnPress: () {},
    ).show();
  }

  String? encodeQueryParameters(Map<String, String> params) {
    return params.entries
        .map((MapEntry<String, String> e) =>
    '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }

  Future<void> _launchURL(String query) async {
    final String encodedQuery = encodeQueryParameters({'q': query}) ?? '';
    final Uri url = Uri.parse('https://www.google.com/search?$encodedQuery%20disease%20management');

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      _showErrorSnackBar('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: <Widget>[
          const SizedBox(height: 20),
          Stack(
            children: [
              Container(
                height: MediaQuery.of(context).size.height * 0.23,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(50.0),
                  ),
                  color: themeColor,
                ),
              ),
              Container(
                height: MediaQuery.of(context).size.height * 0.2,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(50.0),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      spreadRadius: 1,
                      blurRadius: 5,
                      offset: const Offset(2, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: <Widget>[
                    ElevatedButton(
                      onPressed: () {
                        _pickImage(ImageSource.gallery);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: themeColor,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'OPEN GALLERY',
                            style: TextStyle(color: textColor),
                          ),
                          const SizedBox(width: 10),
                          Icon(Icons.image, color: textColor),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        _pickImage(ImageSource.camera);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: themeColor,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('START CAMERA', style: TextStyle(color: textColor)),
                          const SizedBox(width: 10),
                          Icon(Icons.camera_alt, color: textColor),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          _selectedImage == null
              ? SizedBox(
            height: MediaQuery.of(context).size.height * 0.5,
            child: Image.asset('assets/images/pick1.png'),
          )
              : Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.all(20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.file(
                  _selectedImage!,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          if (_selectedImage != null)
            detecting
                ? SpinKitWave(color: themeColor, size: 30)
                : Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeColor,
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  onPressed: detectDisease,
                  child: const Text(
                    'DETECT',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  onPressed: advancedDetect,
                  child: const Text(
                    'ADVANCED DETECT',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          if (modelResult.isNotEmpty)
            Column(
              children: [
                Container(
                  height: MediaQuery.of(context).size.height * 0.2,
                  padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Detected Disease: $modelResult',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: themeColor,
                          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        onPressed: () {
                          _launchURL(modelResult);
                        },
                        child: const Text(
                          'LEARN MORE',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
