import 'package:sembast_web/sembast_web.dart';

Future<Database> openStockDatabase() =>
    databaseFactoryWeb.openDatabase('stockmix');
