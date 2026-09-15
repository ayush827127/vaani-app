import 'dart:math';
import '../../core/db/database_helper.dart';

class DemoDataSeeder {
  static final _random = Random();

  static final _products = [
    {'name': 'Coca Cola 600ml', 'category': 'Soft Drinks', 'cost': 18.0, 'price': 20.0, 'gst': 5.0, 'stock': 48, 'aliases': 'coke,cola,cold drink'},
    {'name': 'Pepsi 600ml', 'category': 'Soft Drinks', 'cost': 18.0, 'price': 20.0, 'gst': 5.0, 'stock': 32, 'aliases': 'pepsi'},
    {'name': 'Sprite 600ml', 'category': 'Soft Drinks', 'cost': 18.0, 'price': 20.0, 'gst': 5.0, 'stock': 25, 'aliases': 'sprite,lemon soda'},
    {'name': 'Thums Up 600ml', 'category': 'Soft Drinks', 'cost': 18.0, 'price': 20.0, 'gst': 5.0, 'stock': 30, 'aliases': 'thumbs up,thums'},
    {'name': 'Limca 600ml', 'category': 'Soft Drinks', 'cost': 18.0, 'price': 20.0, 'gst': 5.0, 'stock': 20, 'aliases': 'limca'},
    {'name': 'Red Bull 250ml', 'category': 'Soft Drinks', 'cost': 90.0, 'price': 110.0, 'gst': 18.0, 'stock': 15, 'aliases': 'red bull,energy drink'},
    {'name': 'Appy Fizz 250ml', 'category': 'Soft Drinks', 'cost': 20.0, 'price': 25.0, 'gst': 5.0, 'stock': 28, 'aliases': 'appy'},
    {'name': 'Mountain Dew 600ml', 'category': 'Soft Drinks', 'cost': 18.0, 'price': 20.0, 'gst': 5.0, 'stock': 22, 'aliases': 'dew,mountain dew'},
    {'name': 'Fanta 600ml', 'category': 'Soft Drinks', 'cost': 18.0, 'price': 20.0, 'gst': 5.0, 'stock': 18, 'aliases': 'fanta,orange soda'},
    {'name': 'Maaza 600ml', 'category': 'Soft Drinks', 'cost': 22.0, 'price': 25.0, 'gst': 5.0, 'stock': 35, 'aliases': 'maaza,mango drink'},
    {'name': 'Lays Classic 26g', 'category': 'Chips', 'cost': 18.0, 'price': 20.0, 'gst': 12.0, 'stock': 6, 'aliases': 'lays,chips'},
    {'name': 'Kurkure 35g', 'category': 'Snacks', 'cost': 18.0, 'price': 20.0, 'gst': 12.0, 'stock': 40, 'aliases': 'kurkure,kur kure'},
    {'name': 'Haldirams Bhujia', 'category': 'Snacks', 'cost': 25.0, 'price': 30.0, 'gst': 12.0, 'stock': 20, 'aliases': 'bhujia,haldirams'},
    {'name': 'Uncle Chips 26g', 'category': 'Chips', 'cost': 18.0, 'price': 20.0, 'gst': 12.0, 'stock': 25, 'aliases': 'uncle chips'},
    {'name': 'Bingo Mad Angles', 'category': 'Chips', 'cost': 18.0, 'price': 20.0, 'gst': 12.0, 'stock': 30, 'aliases': 'bingo,mad angles'},
    {'name': 'Amul Milk 500ml', 'category': 'Dairy', 'cost': 24.0, 'price': 26.0, 'gst': 0.0, 'stock': 50, 'aliases': 'milk,amul milk'},
    {'name': 'Amul Butter 100g', 'category': 'Dairy', 'cost': 50.0, 'price': 55.0, 'gst': 12.0, 'stock': 12, 'aliases': 'butter,amul butter'},
    {'name': 'Amul Cheese Slice', 'category': 'Dairy', 'cost': 75.0, 'price': 85.0, 'gst': 12.0, 'stock': 8, 'aliases': 'cheese'},
    {'name': 'Nestle Yogurt 100g', 'category': 'Dairy', 'cost': 20.0, 'price': 25.0, 'gst': 5.0, 'stock': 15, 'aliases': 'yogurt,curd'},
    {'name': 'Amul Lassi', 'category': 'Dairy', 'cost': 25.0, 'price': 30.0, 'gst': 5.0, 'stock': 18, 'aliases': 'lassi'},
    {'name': 'Dairy Milk 30g', 'category': 'Chocolates', 'cost': 18.0, 'price': 20.0, 'gst': 18.0, 'stock': 60, 'aliases': 'dairy milk,dm'},
    {'name': 'KitKat 35g', 'category': 'Chocolates', 'cost': 20.0, 'price': 25.0, 'gst': 18.0, 'stock': 40, 'aliases': 'kitkat,kit kat'},
    {'name': 'Munch 18g', 'category': 'Chocolates', 'cost': 8.0, 'price': 10.0, 'gst': 18.0, 'stock': 80, 'aliases': 'munch'},
    {'name': 'Eclairs 12g', 'category': 'Chocolates', 'cost': 1.5, 'price': 2.0, 'gst': 18.0, 'stock': 200, 'aliases': 'eclairs,toffee'},
    {'name': '5 Star 36g', 'category': 'Chocolates', 'cost': 18.0, 'price': 20.0, 'gst': 18.0, 'stock': 35, 'aliases': 'five star,5 star'},
    {'name': 'Parle G 100g', 'category': 'Biscuits', 'cost': 8.0, 'price': 10.0, 'gst': 0.0, 'stock': 100, 'aliases': 'parle g,parleg,parle'},
    {'name': 'Good Day 100g', 'category': 'Biscuits', 'cost': 18.0, 'price': 20.0, 'gst': 0.0, 'stock': 60, 'aliases': 'good day,goodday'},
    {'name': 'Marie Gold 120g', 'category': 'Biscuits', 'cost': 22.0, 'price': 25.0, 'gst': 0.0, 'stock': 45, 'aliases': 'marie,marie gold'},
    {'name': 'Bourbon 150g', 'category': 'Biscuits', 'cost': 22.0, 'price': 25.0, 'gst': 0.0, 'stock': 38, 'aliases': 'bourbon'},
    {'name': 'Hide & Seek 120g', 'category': 'Biscuits', 'cost': 28.0, 'price': 32.0, 'gst': 0.0, 'stock': 25, 'aliases': 'hide seek,hide and seek'},
    {'name': 'Maggi 70g', 'category': 'Noodles', 'cost': 12.0, 'price': 15.0, 'gst': 5.0, 'stock': 35, 'aliases': 'maggi,noodles'},
    {'name': 'Top Ramen 70g', 'category': 'Noodles', 'cost': 12.0, 'price': 15.0, 'gst': 5.0, 'stock': 25, 'aliases': 'top ramen,ramen'},
    {'name': 'Yippee Noodles', 'category': 'Noodles', 'cost': 12.0, 'price': 15.0, 'gst': 5.0, 'stock': 30, 'aliases': 'yippee'},
    {'name': 'Sunfeast Pasta', 'category': 'Noodles', 'cost': 20.0, 'price': 25.0, 'gst': 5.0, 'stock': 15, 'aliases': 'pasta,sunfeast pasta'},
    {'name': 'Wai Wai Noodles', 'category': 'Noodles', 'cost': 12.0, 'price': 15.0, 'gst': 5.0, 'stock': 20, 'aliases': 'wai wai'},
    {'name': 'Pepsi Kurkure', 'category': 'Chips', 'cost': 18.0, 'price': 20.0, 'gst': 12.0, 'stock': 28, 'aliases': 'peri peri'},
    {'name': 'Doritos 30g', 'category': 'Chips', 'cost': 28.0, 'price': 35.0, 'gst': 12.0, 'stock': 15, 'aliases': 'doritos'},
    {'name': 'Act II Popcorn', 'category': 'Snacks', 'cost': 15.0, 'price': 20.0, 'gst': 12.0, 'stock': 20, 'aliases': 'popcorn,act ii'},
    {'name': 'Parle G Milk', 'category': 'Biscuits', 'cost': 12.0, 'price': 15.0, 'gst': 0.0, 'stock': 50, 'aliases': 'parle milk'},
    {'name': 'Sunfeast Dark Fantasy', 'category': 'Biscuits', 'cost': 28.0, 'price': 35.0, 'gst': 0.0, 'stock': 20, 'aliases': 'dark fantasy'},
    {'name': 'Surf Excel 500g', 'category': 'Cleaning Products', 'cost': 80.0, 'price': 95.0, 'gst': 18.0, 'stock': 15, 'aliases': 'surf excel,surf'},
    {'name': 'Vim Bar 300g', 'category': 'Cleaning Products', 'cost': 22.0, 'price': 28.0, 'gst': 18.0, 'stock': 20, 'aliases': 'vim'},
    {'name': 'Lizol 500ml', 'category': 'Cleaning Products', 'cost': 70.0, 'price': 85.0, 'gst': 18.0, 'stock': 10, 'aliases': 'lizol,floor cleaner'},
    {'name': 'Harpic 500ml', 'category': 'Cleaning Products', 'cost': 60.0, 'price': 75.0, 'gst': 18.0, 'stock': 12, 'aliases': 'harpic,toilet cleaner'},
    {'name': 'Colin 500ml', 'category': 'Cleaning Products', 'cost': 80.0, 'price': 95.0, 'gst': 18.0, 'stock': 8, 'aliases': 'colin,glass cleaner'},
    {'name': 'Colgate 200g', 'category': 'Personal Care', 'cost': 80.0, 'price': 95.0, 'gst': 18.0, 'stock': 20, 'aliases': 'colgate,toothpaste'},
    {'name': 'Pepsodent 200g', 'category': 'Personal Care', 'cost': 75.0, 'price': 90.0, 'gst': 18.0, 'stock': 15, 'aliases': 'pepsodent'},
    {'name': 'Lux Soap 100g', 'category': 'Personal Care', 'cost': 40.0, 'price': 50.0, 'gst': 18.0, 'stock': 25, 'aliases': 'lux,soap'},
    {'name': 'Dettol Soap 75g', 'category': 'Personal Care', 'cost': 45.0, 'price': 55.0, 'gst': 18.0, 'stock': 20, 'aliases': 'dettol,dettol soap'},
    {'name': 'Head & Shoulders 340ml', 'category': 'Personal Care', 'cost': 200.0, 'price': 245.0, 'gst': 18.0, 'stock': 8, 'aliases': 'head shoulders,shampoo'},
    {'name': 'Ballpoint Pen', 'category': 'Stationery', 'cost': 5.0, 'price': 8.0, 'gst': 12.0, 'stock': 100, 'aliases': 'pen,ballpen'},
    {'name': 'A4 Notebook 200pg', 'category': 'Stationery', 'cost': 50.0, 'price': 65.0, 'gst': 12.0, 'stock': 30, 'aliases': 'notebook,copy'},
    {'name': 'Pencil Set 12pc', 'category': 'Stationery', 'cost': 30.0, 'price': 40.0, 'gst': 12.0, 'stock': 25, 'aliases': 'pencil'},
    {'name': 'Eraser Pack', 'category': 'Stationery', 'cost': 8.0, 'price': 12.0, 'gst': 12.0, 'stock': 40, 'aliases': 'eraser,rubber'},
    {'name': 'Scotch Tape', 'category': 'Stationery', 'cost': 20.0, 'price': 28.0, 'gst': 12.0, 'stock': 20, 'aliases': 'tape,scotch'},
    {'name': 'Tata Salt 1kg', 'category': 'Grocery', 'cost': 18.0, 'price': 22.0, 'gst': 0.0, 'stock': 50, 'aliases': 'salt,tata salt'},
    {'name': 'Tata Tea 500g', 'category': 'Grocery', 'cost': 120.0, 'price': 140.0, 'gst': 5.0, 'stock': 25, 'aliases': 'tea,tata tea,chai'},
    {'name': 'Nescafe Coffee 50g', 'category': 'Grocery', 'cost': 120.0, 'price': 145.0, 'gst': 5.0, 'stock': 12, 'aliases': 'nescafe,coffee'},
    {'name': 'Sugar 1kg', 'category': 'Grocery', 'cost': 40.0, 'price': 48.0, 'gst': 0.0, 'stock': 30, 'aliases': 'sugar,chini'},
    {'name': 'Rice 1kg', 'category': 'Grocery', 'cost': 55.0, 'price': 65.0, 'gst': 0.0, 'stock': 40, 'aliases': 'rice,chawal'},
    {'name': 'Wheat Flour 1kg', 'category': 'Grocery', 'cost': 40.0, 'price': 48.0, 'gst': 0.0, 'stock': 35, 'aliases': 'atta,flour,wheat'},
    {'name': 'Pulses Mixed 500g', 'category': 'Grocery', 'cost': 55.0, 'price': 65.0, 'gst': 0.0, 'stock': 25, 'aliases': 'dal,pulses,daal'},
    {'name': 'Cooking Oil 1L', 'category': 'Grocery', 'cost': 140.0, 'price': 160.0, 'gst': 5.0, 'stock': 20, 'aliases': 'oil,cooking oil,tel'},
    {'name': 'Mustard Oil 1L', 'category': 'Grocery', 'cost': 150.0, 'price': 170.0, 'gst': 5.0, 'stock': 15, 'aliases': 'sarso oil,mustard'},
    {'name': 'Tomato Ketchup 500g', 'category': 'Grocery', 'cost': 70.0, 'price': 85.0, 'gst': 12.0, 'stock': 18, 'aliases': 'ketchup,tomato sauce'},
    {'name': 'Maggi Sauce', 'category': 'Grocery', 'cost': 55.0, 'price': 65.0, 'gst': 12.0, 'stock': 14, 'aliases': 'maggi sauce,hot sauce'},
    {'name': 'Britannia Bread', 'category': 'Grocery', 'cost': 40.0, 'price': 48.0, 'gst': 0.0, 'stock': 20, 'aliases': 'bread,britannia bread'},
    {'name': 'Amul Ghee 500g', 'category': 'Dairy', 'cost': 280.0, 'price': 320.0, 'gst': 12.0, 'stock': 10, 'aliases': 'ghee,amul ghee'},
    {'name': 'Parle Bourbon 75g', 'category': 'Biscuits', 'cost': 15.0, 'price': 20.0, 'gst': 0.0, 'stock': 30, 'aliases': 'bourbon parle'},
    {'name': 'ITC Sunfeast 150g', 'category': 'Biscuits', 'cost': 25.0, 'price': 30.0, 'gst': 0.0, 'stock': 22, 'aliases': 'sunfeast'},
    {'name': 'Frooti 200ml', 'category': 'Soft Drinks', 'cost': 14.0, 'price': 18.0, 'gst': 5.0, 'stock': 40, 'aliases': 'frooti,mango frooti'},
    {'name': 'Slice Mango 600ml', 'category': 'Soft Drinks', 'cost': 22.0, 'price': 28.0, 'gst': 5.0, 'stock': 30, 'aliases': 'slice,mango slice'},
    {'name': 'Real Juice 1L', 'category': 'Soft Drinks', 'cost': 90.0, 'price': 110.0, 'gst': 5.0, 'stock': 15, 'aliases': 'real juice,juice'},
    {'name': 'Glucon D 100g', 'category': 'Grocery', 'cost': 55.0, 'price': 65.0, 'gst': 5.0, 'stock': 12, 'aliases': 'glucon d,glucose'},
    {'name': 'ORS Sachet', 'category': 'Grocery', 'cost': 8.0, 'price': 12.0, 'gst': 5.0, 'stock': 30, 'aliases': 'ors,electrolyte'},
    {'name': 'Hajmola', 'category': 'Snacks', 'cost': 15.0, 'price': 20.0, 'gst': 5.0, 'stock': 25, 'aliases': 'hajmola,candy'},
    {'name': 'Pan Masala', 'category': 'Others', 'cost': 5.0, 'price': 8.0, 'gst': 28.0, 'stock': 100, 'aliases': 'pan masala,pan'},
    {'name': 'Mentos 5pc', 'category': 'Chocolates', 'cost': 1.5, 'price': 2.0, 'gst': 18.0, 'stock': 150, 'aliases': 'mentos,mint'},
    {'name': 'Polo Mint', 'category': 'Chocolates', 'cost': 1.5, 'price': 2.0, 'gst': 18.0, 'stock': 120, 'aliases': 'polo'},
    {'name': 'Boomer Gum', 'category': 'Chocolates', 'cost': 0.5, 'price': 1.0, 'gst': 18.0, 'stock': 200, 'aliases': 'boomer,gum,chewing gum'},
    {'name': 'Big Babol', 'category': 'Chocolates', 'cost': 1.0, 'price': 2.0, 'gst': 18.0, 'stock': 150, 'aliases': 'big babol,bubble gum'},
    {'name': 'Chocos 750g', 'category': 'Grocery', 'cost': 180.0, 'price': 220.0, 'gst': 5.0, 'stock': 8, 'aliases': 'kelloggs chocos,chocos,cereal'},
    {'name': 'Oats 500g', 'category': 'Grocery', 'cost': 60.0, 'price': 75.0, 'gst': 5.0, 'stock': 10, 'aliases': 'oats,quaker oats'},
    {'name': 'Basmati Rice 1kg', 'category': 'Grocery', 'cost': 90.0, 'price': 110.0, 'gst': 0.0, 'stock': 20, 'aliases': 'basmati,biryani rice'},
    {'name': 'Chana Dal 1kg', 'category': 'Grocery', 'cost': 80.0, 'price': 95.0, 'gst': 0.0, 'stock': 15, 'aliases': 'chana dal,chana'},
    {'name': 'Moong Dal 500g', 'category': 'Grocery', 'cost': 70.0, 'price': 85.0, 'gst': 0.0, 'stock': 12, 'aliases': 'moong dal,moong'},
    {'name': 'Tur Dal 1kg', 'category': 'Grocery', 'cost': 120.0, 'price': 140.0, 'gst': 0.0, 'stock': 10, 'aliases': 'tur dal,arhar dal'},
    {'name': 'Chilli Sauce', 'category': 'Grocery', 'cost': 45.0, 'price': 55.0, 'gst': 12.0, 'stock': 10, 'aliases': 'chilli sauce,red sauce'},
    {'name': 'Soy Sauce', 'category': 'Grocery', 'cost': 35.0, 'price': 45.0, 'gst': 12.0, 'stock': 8, 'aliases': 'soy sauce'},
    {'name': 'Vinegar 500ml', 'category': 'Grocery', 'cost': 25.0, 'price': 32.0, 'gst': 12.0, 'stock': 10, 'aliases': 'vinegar,sirka'},
    {'name': 'Amchur Powder 100g', 'category': 'Grocery', 'cost': 30.0, 'price': 38.0, 'gst': 5.0, 'stock': 12, 'aliases': 'amchur,mango powder'},
    {'name': 'Coriander Powder', 'category': 'Grocery', 'cost': 30.0, 'price': 38.0, 'gst': 5.0, 'stock': 15, 'aliases': 'dhania,coriander'},
    {'name': 'Cumin Seeds 100g', 'category': 'Grocery', 'cost': 40.0, 'price': 50.0, 'gst': 5.0, 'stock': 10, 'aliases': 'jeera,cumin'},
  ];

  static final _customerNames = [
    'Rahul Sharma', 'Priya Singh', 'Amit Verma', 'Neha Gupta', 'Suresh Patel',
    'Kavita Joshi', 'Mohit Agarwal', 'Sunita Yadav', 'Deepak Kumar', 'Anjali Mishra',
    'Ravi Shankar', 'Pooja Tiwari', 'Vijay Singh', 'Meena Kumari', 'Arun Pandey',
    'Geeta Devi', 'Sandeep Rana', 'Rekha Verma', 'Ashok Nair', 'Nirmala Devi',
    'Mukesh Sahu', 'Lalita Prasad', 'Sanjay Gupta', 'Kamla Devi', 'Naveen Mishra',
    'Seema Jain', 'Rakesh Yadav', 'Usha Kumari', 'Vinod Sharma', 'Anita Singh',
    'Ramesh Patel', 'Sudha Agarwal', 'Dinesh Kumar', 'Mamta Shukla', 'Mahesh Verma',
    'Kiran Bala', 'Naresh Tiwari', 'Asha Devi', 'Yogesh Joshi', 'Rani Kumari',
    'Pankaj Dubey', 'Sundar Lal', 'Radha Rani', 'Santosh Kumar', 'Vimla Devi',
    'Harish Chandra', 'Sarita Sharma', 'Bharat Singh', 'Champa Devi', 'Sushil Gupta',
    'Ritu Sharma', 'Manish Yadav', 'Savita Jain', 'Gopal Das', 'Preeti Verma',
    'Anil Kumar', 'Pushpa Lata', 'Sunil Srivastava', 'Nisha Pandey', 'Manoj Rai',
    'Lallan Prasad', 'Chameli Devi', 'Devendra Singh', 'Kamlesh Kumar', 'Saroj Bala',
    'Ramkumar Verma', 'Hemlata Devi', 'Jagdish Prasad', 'Rekha Pandey', 'Om Prakash',
    'Indira Devi', 'Rajkumar Singh', 'Sarswati Devi', 'Navin Joshi', 'Prem Lata',
    'Ashutosh Mishra', 'Beena Kumari', 'Dayaram Patel', 'Malti Devi', 'Ravindra Nath',
    'Santosh Kumari', 'Girish Chandra', 'Kamini Devi', 'Shivam Tiwari', 'Manju Lata',
    'Narendra Yadav', 'Meenakshi Devi', 'Bhupendra Singh', 'Sadhana Kumari', 'Rajesh Sahu',
    'Vibha Shukla', 'Jitendra Kumar', 'Chandramukhi', 'Subhash Chandra', 'Rekha Bai',
    'Praveen Sharma', 'Nandini Verma', 'Surya Prakash', 'Rukmini Devi', 'Satendra Singh',
  ];

  static final _phones = List.generate(100, (i) {
    final n = 9000000000 + _random.nextInt(999999999);
    return n.toString();
  });

  static Future<void> seed() async {
    final dbHelper = DatabaseHelper.instance;
    await dbHelper.resetDatabase();
    final db = await dbHelper.database;

    await db.transaction((txn) async {
      // Insert shop
      final now = DateTime.now().toIso8601String();
      final shopId = await txn.insert('shops', {
        'name': 'Gupta General Store',
        'owner_name': 'Ayush Gupta',
        'phone': '9876543210',
        'gst_number': '07ABCDE1234F1Z1',
        'address': '123, Market Road, Delhi - 110001',
        'currency': 'INR',
        'gst_enabled': 1,
        'default_gst_rate': 5.0,
        'created_at': now,
        'updated_at': now,
      });

      // Seed categories from demo products
      final uniqueCategories = _products
          .map((p) => p['category'] as String)
          .toSet()
          .toList()
        ..sort();
      for (final cat in uniqueCategories) {
        await txn.rawInsert(
          'INSERT OR IGNORE INTO categories (shop_id, name, created_at) VALUES (?, ?, ?)',
          [shopId, cat, now],
        );
      }

      // Insert products
      final productIds = <int>[];
      for (final p in _products) {
        final id = await txn.insert('products', {
          'shop_id': shopId,
          'name': p['name'],
          'category': p['category'],
          'cost_price': p['cost'],
          'selling_price': p['price'],
          'gst_rate': p['gst'],
          'stock_quantity': p['stock'],
          'reorder_level': 10,
          'is_active': 1,
          'created_at': now,
          'updated_at': now,
        });
        productIds.add(id);
        // Insert aliases
        for (final alias in (p['aliases'] as String).split(',')) {
          await txn.insert('product_aliases', {
            'product_id': id,
            'alias': alias.trim(),
          });
        }
      }

      // Insert customers
      final customerIds = <int>[];
      final customerNameById = <int, String>{};
      for (int i = 0; i < 100; i++) {
        final id = await txn.insert('customers', {
          'shop_id': shopId,
          'name': _customerNames[i],
          'phone': i < 50 ? _phones[i] : null,
          'total_purchases': 0,
          'total_bills': 0,
          'created_at': DateTime.now().subtract(Duration(days: _random.nextInt(365))).toIso8601String(),
          'updated_at': now,
        });
        customerIds.add(id);
        customerNameById[id] = _customerNames[i];
      }

      // Generate 100 invoices
      final summaryMap = <String, Map<String, dynamic>>{};
      for (int invNum = 1; invNum <= 100; invNum++) {
        final daysBack = _random.nextInt(365);
        final invDate = DateTime.now().subtract(Duration(days: daysBack));
        final dateStr = invDate.toIso8601String().substring(0, 10);
        final ym = '${invDate.year}${invDate.month.toString().padLeft(2, '0')}';

        final isWalkIn = _random.nextDouble() < 0.3;
        final customerId = isWalkIn ? null : customerIds[_random.nextInt(customerIds.length)];
        final itemCount = _random.nextInt(5) + 1;
        final paymentMode = _random.nextDouble() < 0.8 ? 'cash' : 'upi';

        double subtotal = 0, gstAmount = 0, totalCost = 0;
        final cartItems = <Map<String, dynamic>>[];
        for (int j = 0; j < itemCount; j++) {
          final pIdx = _random.nextInt(productIds.length);
          final product = _products[pIdx];
          final qty = _random.nextInt(4) + 1;
          final price = (product['price'] as double);
          final cost = (product['cost'] as double);
          final gstRate = (product['gst'] as double);
          final lineTotal = qty * price;
          final lineGst = lineTotal * gstRate / 100;
          subtotal += lineTotal;
          gstAmount += lineGst;
          totalCost += qty * cost;
          cartItems.add({
            'product_id': productIds[pIdx],
            'product_name': product['name'],
            'quantity': qty,
            'selling_price': price,
            'gst_rate': gstRate,
            'gst_amount': lineGst,
            'line_total': lineTotal,
          });
        }
        final grandTotal = subtotal + gstAmount;
        final seqPad = invNum.toString().padLeft(6, '0');
        final invoiceNum = 'INV-$ym-$seqPad';
        final invId = await txn.insert('invoices', {
          'invoice_number': invoiceNum,
          'shop_id': shopId,
          'customer_id': customerId,
          'customer_name': customerId == null ? 'Walk-in Customer' : customerNameById[customerId]!,
          'subtotal': subtotal,
          'discount_type': 'none',
          'discount_value': 0,
          'discount_amount': 0,
          'gst_amount': gstAmount,
          'grand_total': grandTotal,
          'payment_mode': paymentMode,
          'status': 'paid',
          'created_at': invDate.toIso8601String(),
        });

        for (final item in cartItems) {
          await txn.insert('invoice_items', {'invoice_id': invId, ...item});
        }

        // Update customer stats
        if (customerId != null) {
          await txn.rawUpdate('''
            UPDATE customers SET total_purchases = total_purchases + ?, total_bills = total_bills + 1, last_visit = ?
            WHERE id = ?
          ''', [grandTotal, invDate.toIso8601String(), customerId]);
        }

        // Update sales summary
        if (!summaryMap.containsKey(dateStr)) {
          summaryMap[dateStr] = {'sales': 0.0, 'cost': 0.0, 'bills': 0, 'items': 0};
        }
        summaryMap[dateStr]!['sales'] = (summaryMap[dateStr]!['sales'] as double) + grandTotal;
        summaryMap[dateStr]!['cost'] = (summaryMap[dateStr]!['cost'] as double) + totalCost;
        summaryMap[dateStr]!['bills'] = (summaryMap[dateStr]!['bills'] as int) + 1;
        summaryMap[dateStr]!['items'] = (summaryMap[dateStr]!['items'] as int) + cartItems.fold<int>(0, (s, i) => s + (i['quantity'] as int));
      }

      // Insert sales summary
      for (final entry in summaryMap.entries) {
        final s = entry.value;
        await txn.insert('sales_summary', {
          'date': entry.key,
          'total_sales': s['sales'],
          'total_cost': s['cost'],
          'total_profit': (s['sales'] as double) - (s['cost'] as double),
          'total_bills': s['bills'],
          'total_items_sold': s['items'],
          'updated_at': now,
        });
      }

      // Insert demo notifications
      final notifTypes = [
        {'type': 'low_stock', 'title': 'Low Stock Alert', 'message': 'Lays Classic is running low (6 units left). Time to reorder!'},
        {'type': 'milestone', 'title': 'Sales Milestone', 'message': "Today's sales exceeded ₹10,000. Keep it up! 🎉"},
        {'type': 'record', 'title': 'New Record', 'message': 'You generated 84 invoices today — a new record!'},
        {'type': 'update', 'title': 'Inventory Update', 'message': 'Maggi stock updated to 35 units.'},
        {'type': 'low_stock', 'title': 'Low Stock Alert', 'message': 'Parle G stock is low (8 units). Reorder soon.'},
        {'type': 'milestone', 'title': 'Monthly Goal', 'message': "You've crossed ₹2 Lakh in monthly sales! 🚀"},
        {'type': 'update', 'title': 'New Customer', 'message': 'Ritu Sharma registered as a new customer.'},
        {'type': 'record', 'title': 'Best Week', 'message': 'This week was your best ever! ₹68,450 in revenue.'},
        {'type': 'low_stock', 'title': 'Low Stock Alert', 'message': 'Pepsi 600ml stock is low (5 units). Reorder!'},
        {'type': 'update', 'title': 'Daily Summary', 'message': 'Today: ₹12,450 in 84 bills. Profit: ₹3,890.'},
      ];
      for (final n in notifTypes) {
        await txn.insert('notifications', {
          ...n,
          'is_read': 0,
          'created_at': DateTime.now().subtract(Duration(minutes: _random.nextInt(1440))).toIso8601String(),
        });
      }
    });
  }
}
