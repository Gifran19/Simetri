import 'package:flutter/material.dart';
import '../models/device_data.dart';


class HeaderCard extends StatelessWidget {


  final DeviceData device;

  final VoidCallback onConnect;



  const HeaderCard({

    super.key,

    required this.device,

    required this.onConnect,

  });



  @override
  Widget build(BuildContext context){


    return Container(


      padding:
      const EdgeInsets.all(20),


      decoration:BoxDecoration(


        color:Colors.white,


        borderRadius:
        BorderRadius.circular(25),


      ),



      child:Column(


        crossAxisAlignment:
        CrossAxisAlignment.start,



        children:[



          Row(


            mainAxisAlignment:
            MainAxisAlignment.spaceBetween,


            children:[



              Image.asset(

                "assets/logo.png",

                width:80,

              ),



              ClipRRect(


                borderRadius:
                BorderRadius.circular(15),



                child:Image.asset(

                  "assets/house.png",

                  width:90,

                  height:90,

                  fit:BoxFit.cover,

                ),


              )



            ],


          ),




          const SizedBox(height:20),




          const Text(

            "Selamat Datang",

            style:TextStyle(

              fontSize:16,

              color:Colors.grey,

            ),

          ),




          const Text(

            "Smart Meter Online",

            style:TextStyle(

              fontSize:24,

              fontWeight:
              FontWeight.bold,

            ),

          ),




          const SizedBox(height:8),



          const Text(

            "Pantau penggunaan listrik rumah Anda secara real-time",

          ),



          const SizedBox(height:20),




          ElevatedButton.icon(


            onPressed:

            device.isConnected

                ? null

                : onConnect,



            icon:Icon(

              device.isConnected

                  ? Icons.wifi

                  : Icons.bluetooth,

            ),



            label:Text(

              device.isConnected

                  ?

              "Perangkat Terhubung"

                  :

              "Hubungkan Perangkat",

            ),


          )


        ],


      ),


    );


  }
}