import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';



class MonthlyCostChart extends StatelessWidget {


  const MonthlyCostChart({super.key});



  @override
  Widget build(BuildContext context){



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


                "Perbandingan Biaya Bulanan",


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


                decoration:

                BoxDecoration(


                  borderRadius:
                  BorderRadius.circular(15),


                  border:

                  Border.all(

                    color:
                    Colors.grey.shade300,

                  ),


                ),



                child:

                const Text(

                  "Tahun 2026",

                  style:

                  TextStyle(

                    fontSize:11,

                  ),

                ),



              )



            ],



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




                titlesData:

                const FlTitlesData(

                  show:false,

                ),




                barGroups:


                List.generate(12,(index){



                  return BarChartGroupData(


                    x:index,


                    barRods:[



                      BarChartRodData(


                        toY:

                        60,


                        width:12,



                        color:

                        const Color(0xff00A896),



                        borderRadius:

                        BorderRadius.circular(3),



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