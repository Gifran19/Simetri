import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';



class MonthlyEnergyChart extends StatelessWidget {


  const MonthlyEnergyChart({super.key});



  @override
  Widget build(BuildContext context){


    return chart();


  }



  Widget chart(){


    return Container(


      padding:
      const EdgeInsets.all(15),


      decoration:BoxDecoration(

        color:Colors.white,

        borderRadius:
        BorderRadius.circular(20),

      ),



      child:Column(

        crossAxisAlignment:
        CrossAxisAlignment.start,


        children:[



          const Text(

            "Pemakaian Energi Bulan ini",

            style:TextStyle(

              fontSize:17,

              fontWeight:
              FontWeight.bold,

            ),

          ),



          const SizedBox(height:20),



          SizedBox(

            height:250,


            child:BarChart(


              BarChartData(


                borderData:
                FlBorderData(

                  show:false,

                ),



                gridData:
                FlGridData(

                  show:true,

                  drawVerticalLine:false,

                ),




                barGroups:


                List.generate(12,(index){


                  return BarChartGroupData(

                      x:index,


                      barRods:[


                        BarChartRodData(

                          toY: [
                            65,
                            70,
                            68,
                            72,
                            60,
                            64,
                            66,
                            62,
                            70,
                            65,
                            68,
                            75,
                          ][index].toDouble(),



                          width:12,


                          color:
                          const Color(0xff00A896),


                          borderRadius:
                          BorderRadius.circular(3),

                        )



                      ]

                  );


                }),



              ),


            ),



          )



        ],


      ),


    );


  }


}