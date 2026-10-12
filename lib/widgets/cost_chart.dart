import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'energy_chart.dart';



class CostChart extends StatelessWidget {


  const CostChart({super.key});



  @override
  Widget build(BuildContext context){


    return Container(

      padding:
      const EdgeInsets.all(15),


      decoration:BoxDecoration(

        color:Colors.white,

        borderRadius:
        BorderRadius.circular(20),

        border:
        Border.all(
          color:Colors.grey.shade300,
        ),

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

                "Perbandingan Biaya",

                style:TextStyle(

                  fontSize:17,

                  fontWeight:
                  FontWeight.bold,

                ),

              ),



              const Text(

                "↓ 27%\nLebih hemat",

                textAlign:
                TextAlign.right,

                style:TextStyle(

                  color:Colors.green,

                  fontSize:12,

                ),

              )


            ],

          ),



          const SizedBox(height:15),



          SizedBox(

            height:220,


            child:LineChart(

              LineChartData(


                gridData:
                FlGridData(

                  show:true,

                  drawVerticalLine:false,

                ),



                titlesData:
                const FlTitlesData(

                  show:false,

                ),



                borderData:
                FlBorderData(

                  show:false,

                ),



                lineBarsData:[


                  EnergyLine(

                    values:[
                      120,150,110,160,130
                    ],

                    color:
                    const Color(0xff0066CC),

                  ),



                  EnergyLine(

                    values:[
                      70,90,60,100,80
                    ],

                    color:
                    const Color(0xffffb703),

                  ),



                ],


              ),


            ),


          ),


        ],


      ),
    );
  }
}





LineChartBarData EnergyLine({

  required List<double> values,

  required Color color,

}){


  return LineChartBarData(


    spots:

    values.asMap().entries.map(

            (e)=>

            FlSpot(

              e.key.toDouble(),

              e.value,

            )

    ).toList(),



    isCurved:true,


    color:color,


    barWidth:3,


    dotData:
    const FlDotData(

      show:false,

    ),



    belowBarData:

    BarAreaData(

      show:true,

      color:
      color.withOpacity(0.15),

    ),


  );


}