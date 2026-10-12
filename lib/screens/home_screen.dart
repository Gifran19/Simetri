import 'package:flutter/material.dart';

import '../models/device_data.dart';
import '../widgets/header_card.dart';
import '../widgets/monitoring_card.dart';
import '../widgets/energy_chart.dart';
import '../widgets/cost_chart.dart';

import 'energy_screen.dart';

class HomeScreen extends StatefulWidget {

  const HomeScreen({super.key});


  @override
  State<HomeScreen> createState() => _HomeScreenState();

}



class _HomeScreenState extends State<HomeScreen>{


  DeviceData device = DeviceData(

    isConnected: false,

    connectionType: "Wi-Fi",

    voltage: 0,

    current: 0,

    power: 0,

    energy: 0,

  );



  // sementara simulasi koneksi IoT
  // nanti diganti Firebase / API ESP32

  void connectDevice(){


    setState(() {


      device = DeviceData(

        isConnected:true,

        connectionType:"Wi-Fi",

        voltage:221,

        current:0.1,

        power:14.2,

        energy:42.5,

      );


    });


  }




  @override
  Widget build(BuildContext context) {


    return Scaffold(


      backgroundColor:
      const Color(0xffF8FAFC),



      bottomNavigationBar:
      BottomNavigationBar(

        currentIndex:0,


        onTap:(index){


          if(index == 1){


            Navigator.push(

              context,

              MaterialPageRoute(

                builder:(context)=>
                const EnergyScreen(),

              ),

            );


          }


        },



        selectedItemColor:
        const Color(0xff003B73),



        items:const[


          BottomNavigationBarItem(

            icon:Icon(Icons.home),

            label:"Home",

          ),



          BottomNavigationBarItem(

            icon:Icon(Icons.bolt),

            label:"Energy",

          ),


        ],


      ),




      body:SafeArea(


        child:SingleChildScrollView(


          padding:
          const EdgeInsets.all(20),



          child:Column(


            crossAxisAlignment:
            CrossAxisAlignment.start,

            children:[
              HeaderCard(

                device:device,

                onConnect:connectDevice,

              ),




              const SizedBox(height:20),




              if(device.isConnected)


                Column(

                  children:[



                    MonitoringCard(

                      device:device,

                    ),




                    const SizedBox(height:20),



                    const EnergyChart(),




                    const SizedBox(height:20),




                    const CostChart(),



                  ],

                )

              else


                Container(


                  padding:
                  const EdgeInsets.all(25),



                  decoration:BoxDecoration(


                    color:Colors.white,


                    borderRadius:
                    BorderRadius.circular(20),


                  ),



                  child:const Column(


                    children:[


                      Icon(

                        Icons.wifi_off,

                        size:60,

                        color:Colors.grey,

                      ),



                      SizedBox(height:15),



                      Text(

                        "Perangkat belum terhubung",

                        style:TextStyle(

                          fontWeight:
                          FontWeight.bold,

                          fontSize:18,

                        ),

                      ),



                      SizedBox(height:8),



                      Text(

                        "Hubungkan Smart Meter untuk melihat data listrik",

                        textAlign:
                        TextAlign.center,

                      )

                    ],


                  ),

                )
            ],
          ),
        ),
      ),
    );
  }
}