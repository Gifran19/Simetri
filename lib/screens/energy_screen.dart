import 'package:flutter/material.dart';

import '../widgets/summary_card.dart';
import '../widgets/monthly_energy_chart.dart';
import '../widgets/daily_energy_chart.dart';
import '../widgets/monthly_cost_chart.dart';

import 'home_screen.dart';

class EnergyScreen extends StatelessWidget {


  const EnergyScreen({super.key});



  @override
  Widget build(BuildContext context){


    return Scaffold(


      backgroundColor:
      const Color(0xffF8FAFC),



      bottomNavigationBar:
      BottomNavigationBar(

        currentIndex:1,


        onTap:(index){


          if(index == 0){


            Navigator.pop(context);


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



              const Text(

                "SIMETRI",

                style:TextStyle(

                  fontSize:26,

                  fontWeight:
                  FontWeight.bold,

                  color:
                  Color(0xff003B73),

                ),

              ),




              const SizedBox(height:5),




              const Text(

                "Analisis Energy",

                style:TextStyle(

                  fontSize:22,

                  fontWeight:
                  FontWeight.bold,

                ),

              ),




              const SizedBox(height:5),




              const Text(

                "Lihat detail pemakaian energi rumah Anda",

                style:TextStyle(

                  color:Colors.grey,

                ),

              ),




              const SizedBox(height:20),





              Row(

                children:[



                  Expanded(

                    child:SummaryCard(

                      icon:Icons.bolt,

                      title:
                      "Total Pemakaian",

                      value:
                      "42.5 kWh",

                    ),

                  ),



                  const SizedBox(width:15),



                  Expanded(

                    child:SummaryCard(

                      icon:Icons.wallet,

                      title:
                      "Total Pemakaian",

                      value:
                      "Rp 64.000",

                    ),

                  ),


                ],

              ),




              const SizedBox(height:25),





              const MonthlyEnergyChart(),



              const SizedBox(height:25),





              const DailyEnergyChart(),



              const SizedBox(height:25),





              const MonthlyCostChart(),
            ],
          ),
        ),
      ),
    );
  }
}