import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const String _openWeatherApiKey = 'b69dbc6492c3a7d2afc29f48ee9ffeac';

class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  Timer? _debounce;
  bool _isLoading = true;
  bool _isSearching = false;
  String? _errorMessage;
  String _selectedLocation = 'Kuala Lumpur';
  WeatherData? _weatherData;
  List<LocationSuggestion> _suggestions = <LocationSuggestion>[];

  @override
  void initState() {
    super.initState();
    _loadWeatherForCity(_selectedLocation);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadWeatherForCity(String city) async {
    if (city.trim().isEmpty) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _selectedLocation = city.trim();
    });

    try {
      final uri = Uri.parse(
        'https://api.openweathermap.org/data/2.5/weather?q=${Uri.encodeComponent(city.trim())}&units=metric&appid=$_openWeatherApiKey',
      );
      final response = await http.get(uri);

      if (response.statusCode != 200) {
        throw Exception(
          _describeOpenWeatherFailure(response, fallbackLabel: '"$city"'),
        );
      }

      final Map<String, dynamic> json =
          jsonDecode(response.body) as Map<String, dynamic>;
      final weather = WeatherData.fromJson(json);

      if (!mounted) {
        return;
      }

      setState(() {
        _weatherData = weather;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage = error.toString();
      });
    }
  }

  Future<void> _loadWeatherForSuggestion(LocationSuggestion suggestion) async {
    setState(() {
      _isSearching = false;
      _suggestions = <LocationSuggestion>[];
      _searchController.text = suggestion.displayName;
      _searchController.selection = TextSelection.fromPosition(
        TextPosition(offset: _searchController.text.length),
      );
    });

    await _loadWeatherForCoordinates(
      suggestion.latitude,
      suggestion.longitude,
      suggestion.displayName,
    );
  }

  Future<void> _loadWeatherForCoordinates(
    double latitude,
    double longitude,
    String displayName,
  ) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _selectedLocation = displayName;
    });

    try {
      final uri = Uri.parse(
        'https://api.openweathermap.org/data/2.5/weather?lat=$latitude&lon=$longitude&units=metric&appid=$_openWeatherApiKey',
      );
      final response = await http.get(uri);

      if (response.statusCode != 200) {
        throw Exception(
          _describeOpenWeatherFailure(
            response,
            fallbackLabel: '"$displayName"',
          ),
        );
      }

      final Map<String, dynamic> json =
          jsonDecode(response.body) as Map<String, dynamic>;
      final weather = WeatherData.fromJson(json);

      if (!mounted) {
        return;
      }

      setState(() {
        _weatherData = weather;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage = error.toString();
      });
    }
  }

  Future<void> _searchLocations(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _suggestions = <LocationSuggestion>[];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final uri = Uri.parse(
        'https://api.openweathermap.org/geo/1.0/direct?q=${Uri.encodeComponent(query.trim())}&limit=5&appid=$_openWeatherApiKey',
      );
      final response = await http.get(uri);

      if (response.statusCode != 200) {
        throw Exception(
          _describeOpenWeatherFailure(
            response,
            fallbackLabel: 'location search',
          ),
        );
      }

      final List<dynamic> json = jsonDecode(response.body) as List<dynamic>;
      final suggestions = json
          .map(
            (item) => LocationSuggestion.fromJson(item as Map<String, dynamic>),
          )
          .where((item) => item.displayName.isNotEmpty)
          .toList();

      if (!mounted) {
        return;
      }

      setState(() {
        _suggestions = suggestions;
        _isSearching = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _suggestions = <LocationSuggestion>[];
        _isSearching = false;
      });
    }
  }

  void _handleSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _searchLocations(value);
    });

    setState(() {});
  }

  Color _backgroundTopColor(WeatherData? data) {
    final condition = data?.condition.toLowerCase() ?? '';
    if (condition.contains('rain') ||
        condition.contains('drizzle') ||
        condition.contains('thunderstorm')) {
      return const Color(0xFF30415D);
    }
    if (condition.contains('cloud')) {
      return const Color(0xFF4A6FA5);
    }
    if (condition.contains('snow')) {
      return const Color(0xFF89A9C4);
    }
    return const Color(0xFFFB8C00);
  }

  String _weatherSummary(WeatherData? data) {
    if (data == null) {
      return 'Search for a location to see the weather';
    }

    final condition = data.condition.toLowerCase();
    if (condition.contains('clear')) {
      return 'Sunny';
    }
    if (condition.contains('cloud')) {
      return 'Cloudy';
    }
    if (condition.contains('rain')) {
      return 'Rainy';
    }
    if (condition.contains('drizzle')) {
      return 'Drizzly';
    }
    if (condition.contains('snow')) {
      return 'Snowy';
    }
    if (condition.contains('thunderstorm')) {
      return 'Stormy';
    }
    return data.condition;
  }

  String _describeOpenWeatherFailure(
    http.Response response, {
    required String fallbackLabel,
  }) {
    String message = 'Unable to load weather for $fallbackLabel.';

    try {
      final dynamic decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final apiMessage = (decoded['message'] as String? ?? '').trim();
        if (response.statusCode == 401) {
          return 'Invalid OpenWeather API key. Replace the key in lib/screen.dart with a valid key.';
        }
        if (apiMessage.isNotEmpty) {
          message =
              '$message ${apiMessage[0].toUpperCase()}${apiMessage.substring(1)}.';
        }
      }
    } catch (_) {
      if (response.statusCode == 401) {
        return 'Invalid OpenWeather API key. Replace the key in lib/screen.dart with a valid key.';
      }
    }

    return message;
  }

  @override
  Widget build(BuildContext context) {
    final weather = _weatherData;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color(0xFF10172A),
              Color(0xFF18263F),
              Color(0xFF1B2336),
            ],
            stops: <double>[0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: <Widget>[
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        'OpenWeather',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(32),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.10),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              children: <Widget>[
                                Expanded(
                                  child: Center(
                                    child: _isLoading
                                        ? const CircularProgressIndicator(
                                            color: Colors.white,
                                          )
                                        : _errorMessage != null
                                        ? Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: <Widget>[
                                              const Icon(
                                                Icons.cloud_off,
                                                size: 72,
                                                color: Colors.white70,
                                              ),
                                              const SizedBox(height: 16),
                                              Text(
                                                _errorMessage ??
                                                    'Something went wrong',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              const SizedBox(height: 12),
                                              FilledButton(
                                                onPressed: () =>
                                                    _loadWeatherForCity(
                                                      _selectedLocation,
                                                    ),
                                                child: const Text('Try again'),
                                              ),
                                            ],
                                          )
                                        : Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: <Widget>[
                                              Container(
                                                width: 260,
                                                height: 260,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  gradient: LinearGradient(
                                                    colors: <Color>[
                                                      _backgroundTopColor(
                                                        weather,
                                                      ).withValues(alpha: 0.85),
                                                      _backgroundTopColor(
                                                        weather,
                                                      ).withValues(alpha: 0.35),
                                                    ],
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                  ),
                                                  boxShadow: <BoxShadow>[
                                                    BoxShadow(
                                                      color: Colors.black
                                                          .withValues(
                                                            alpha: 0.20,
                                                          ),
                                                      blurRadius: 24,
                                                      offset: const Offset(
                                                        0,
                                                        14,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                child: ClipOval(
                                                  child:
                                                      weather
                                                              ?.iconCode
                                                              .isNotEmpty ==
                                                          true
                                                      ? Image.network(
                                                          'https://openweathermap.org/img/wn/${weather!.iconCode}@4x.png',
                                                          fit: BoxFit.cover,
                                                          errorBuilder: (_, __, ___) {
                                                            return const Icon(
                                                              Icons
                                                                  .wb_sunny_rounded,
                                                              size: 156,
                                                              color:
                                                                  Colors.white,
                                                            );
                                                          },
                                                        )
                                                      : const Icon(
                                                          Icons
                                                              .wb_sunny_rounded,
                                                          size: 156,
                                                          color: Colors.white,
                                                        ),
                                                ),
                                              ),
                                              const SizedBox(height: 50),
                                              Text(
                                                '${weather?.temperature.round() ?? '--'}°',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 100,
                                                  fontWeight: FontWeight.w800,
                                                  height: 1,
                                                ),
                                              ),
                                              const SizedBox(height: 10),
                                              Text(
                                                _weatherSummary(weather),
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 40,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 10),
                                              Text(
                                                _selectedLocation,
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: <Widget>[
                                      TextField(
                                        controller: _searchController,
                                        focusNode: _searchFocusNode,
                                        onChanged: _handleSearchChanged,
                                        onSubmitted: _loadWeatherForCity,
                                        textInputAction: TextInputAction.search,
                                        decoration: InputDecoration(
                                          hintText: 'Search location',
                                          border: InputBorder.none,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 18,
                                                vertical: 16,
                                              ),
                                          prefixIcon: const Icon(Icons.search),
                                          suffixIcon: _isSearching
                                              ? const Padding(
                                                  padding: EdgeInsets.all(14),
                                                  child: SizedBox(
                                                    width: 16,
                                                    height: 16,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                  ),
                                                )
                                              : IconButton(
                                                  icon: const Icon(
                                                    Icons.my_location,
                                                  ),
                                                  onPressed: () {
                                                    _searchController.text =
                                                        _selectedLocation;
                                                    _searchController
                                                            .selection =
                                                        TextSelection.fromPosition(
                                                          TextPosition(
                                                            offset:
                                                                _searchController
                                                                    .text
                                                                    .length,
                                                          ),
                                                        );
                                                    _loadWeatherForCity(
                                                      _selectedLocation,
                                                    );
                                                  },
                                                ),
                                        ),
                                      ),
                                      if (_suggestions.isNotEmpty)
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            maxHeight: 120,
                                          ),
                                          child: ListView.separated(
                                            shrinkWrap: true,
                                            itemCount: _suggestions.length,
                                            separatorBuilder: (_, __) =>
                                                const Divider(height: 1),
                                            itemBuilder: (context, index) {
                                              final suggestion =
                                                  _suggestions[index];
                                              return ListTile(
                                                dense: true,
                                                title: Text(
                                                  suggestion.displayName,
                                                ),
                                                subtitle: Text(
                                                  '${suggestion.latitude.toStringAsFixed(2)}, ${suggestion.longitude.toStringAsFixed(2)}',
                                                ),
                                                onTap: () =>
                                                    _loadWeatherForSuggestion(
                                                      suggestion,
                                                    ),
                                              );
                                            },
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WeatherData {
  const WeatherData({
    required this.locationName,
    required this.temperature,
    required this.condition,
    required this.iconCode,
  });

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    final List<dynamic> weatherList =
        json['weather'] as List<dynamic>? ?? <dynamic>[];
    final Map<String, dynamic> weather = weatherList.isNotEmpty
        ? weatherList.first as Map<String, dynamic>
        : <String, dynamic>{};
    final Map<String, dynamic> main =
        json['main'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final Map<String, dynamic> sys =
        json['sys'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final String cityName = (json['name'] as String? ?? 'Unknown location')
        .trim();
    final String country = (sys['country'] as String? ?? '').trim();

    return WeatherData(
      locationName: country.isEmpty ? cityName : '$cityName, $country',
      temperature: (main['temp'] as num? ?? 0).toDouble(),
      condition: (weather['description'] as String? ?? 'Unknown').trim(),
      iconCode: (weather['icon'] as String? ?? '').trim(),
    );
  }

  final String locationName;
  final double temperature;
  final String condition;
  final String iconCode;
}

class LocationSuggestion {
  const LocationSuggestion({
    required this.displayName,
    required this.latitude,
    required this.longitude,
  });

  factory LocationSuggestion.fromJson(Map<String, dynamic> json) {
    final String name = (json['name'] as String? ?? '').trim();
    final String country = (json['country'] as String? ?? '').trim();
    final String state = (json['state'] as String? ?? '').trim();

    final parts = <String>[
      name,
      if (state.isNotEmpty) state,
      if (country.isNotEmpty) country,
    ];

    return LocationSuggestion(
      displayName: parts.join(', '),
      latitude: (json['lat'] as num).toDouble(),
      longitude: (json['lon'] as num).toDouble(),
    );
  }

  final String displayName;
  final double latitude;
  final double longitude;
}
