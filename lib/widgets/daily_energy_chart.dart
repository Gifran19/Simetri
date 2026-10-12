import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';


class DailyEnergyChart extends StatelessWidget {


  const DailyEnergyChart({super.key});



  @override
  Widget build(BuildContext context) {


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



          Row(


            mainAxisAlignment:
            MainAxisAlignment.spaceBetween,



            children:[



              const Text(

                "Pemakaian Energi Harian",

                style:TextStyle(

                  fontSize:17,

                  fontWeight:
                  FontWeight.bold,

                ),

              ),




              Container(

                padding:
                const EdgeInsets.symmetric(

                  horizontal:10,

                  vertical:5,

                ),


                decoration:BoxDecoration(

                  borderRadius:
                  BorderRadius.circular(15),

                  border:
                  Border.all(

                    color:
                    Colors.grey.shade300,

                  ),

                ),


                child:const Text(

                  "7 hari terakhir",

                  style:TextStyle(

                    fontSize:11,

                  ),

                ),

              )



            ],

          ),



          const SizedBox(height:20),




          SizedBox(

            height:230,


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




                titlesData:

                FlTitlesData(



                  bottomTitles:

                  AxisTitles(


                    sideTitles:

                    SideTitles(


                      showTitles:true,


                      getTitlesWidget:

                          (value,meta){



                        const days=[

                          "Sen",

                          "Sel",

                          "Rab",

                          "Kam",

                          "Jum",

                          "Sab",

                          "Min"

                        ];



                        return Text(

                          days[value.toInt()],

                          style:

                          const TextStyle(

                            fontSize:10,

                          ),

                        );


                      },



                    ),


                  ),



                  leftTitles:

                  const AxisTitles(

                    sideTitles:

                    SideTitles(

                      showTitles:false,

                    ),

                  ),




                  rightTitles:

                  const AxisTitles(

                    sideTitles:

                    SideTitles(

                      showTitles:false,

                    ),

                  ),



                  topTitles:

                  const AxisTitles(

                    sideTitles:

                    SideTitles(

                      showTitles:false,

                    ),

                  ),



                ),




                barGroups:



                List.generate(7,(index){



                  return BarChartGroupData(

                    x:index,

                    barRods:[



                      BarChartRodData(

                        toY: [
                          2,
                          3,
                          2,
                          4,
                          5,
                          10,
                          14,
                        ][index].toDouble(),



                        width:18,


                        color:

                        const Color(0xff00A896),



                        borderRadius:

                        BorderRadius.circular(4),


                      )



                    ],



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