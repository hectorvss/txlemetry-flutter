package com.txlemetry.flutter

import android.os.Handler
import android.os.Looper
import com.txlemetry.surveys.OnTxlemetrySurveyClosed
import com.txlemetry.surveys.OnTxlemetrySurveyResponse
import com.txlemetry.surveys.OnTxlemetrySurveyShown
import com.txlemetry.surveys.TxlemetryDisplayChoiceQuestion
import com.txlemetry.surveys.TxlemetryDisplayLinkQuestion
import com.txlemetry.surveys.TxlemetryDisplayOpenQuestion
import com.txlemetry.surveys.TxlemetryDisplayRatingQuestion
import com.txlemetry.surveys.TxlemetryDisplaySurvey
import com.txlemetry.surveys.TxlemetryDisplaySurveyQuestion
import com.txlemetry.surveys.TxlemetryNextSurveyQuestion
import com.txlemetry.surveys.TxlemetrySurveyResponse
import com.txlemetry.surveys.TxlemetrySurveysResumeAwareDelegate
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/**
 * Separate surveys delegate to avoid class loading issues in the main plugin
 */
class TxlemetryFlutterSurveysDelegate(
    private val channel: MethodChannel,
) : TxlemetrySurveysResumeAwareDelegate {
    override val supportsSurveyResume: Boolean = true

    @Volatile
    private var presentationId: String? = null
    private var currentSurvey: TxlemetryDisplaySurvey? = null
    private var onSurveyShownCallback: OnTxlemetrySurveyShown? = null
    private var onSurveyResponseCallback: OnTxlemetrySurveyResponse? = null
    private var onSurveyClosedCallback: OnTxlemetrySurveyClosed? = null

    override fun renderSurvey(
        survey: TxlemetryDisplaySurvey,
        onSurveyShown: OnTxlemetrySurveyShown,
        onSurveyResponse: OnTxlemetrySurveyResponse,
        onSurveyClosed: OnTxlemetrySurveyClosed,
    ) {
        val presentation = UUID.randomUUID().toString()
        presentationId = presentation
        currentSurvey = survey
        onSurveyShownCallback = onSurveyShown
        onSurveyResponseCallback = onSurveyResponse
        onSurveyClosedCallback = onSurveyClosed

        // Convert survey to map and send to Flutter
        Handler(Looper.getMainLooper()).post {
            if (presentationId == presentation) {
                channel.invokeMethod("showSurvey", survey.toMap() + ("presentationId" to presentation))
            }
        }
    }

    override fun cleanupSurveys() {
        presentationId = null
        currentSurvey = null
        onSurveyShownCallback = null
        onSurveyResponseCallback = null
        onSurveyClosedCallback = null
        invokeFlutterMethod("hideSurveys")
    }

    fun handleSurveyAction(
        action: String,
        payload: Map<String, Any>?,
        result: MethodChannel.Result,
    ) {
        val survey = currentSurvey
        if (survey == null || presentationId == null || payload?.get("presentationId") != presentationId) {
            result.error("SurveyInvalidated", "Survey presentation is no longer active", null)
            return
        }

        when (action) {
            "shown" -> {
                onSurveyShownCallback?.invoke(survey)
            }

            "response" -> {
                val index = payload?.get("index") as? Int
                val responsePayload = payload?.get("response")

                if (index != null && index in survey.questions.indices) {
                    val question = survey.questions[index]

                    // Create TxlemetrySurveyResponse based on question type
                    val surveyResponse =
                        when (question) {
                            is TxlemetryDisplayLinkQuestion -> {
                                // For link questions
                                val boolValue = responsePayload as? Boolean ?: false
                                TxlemetrySurveyResponse.Link(boolValue)
                            }

                            is TxlemetryDisplayRatingQuestion -> {
                                // For rating questions
                                val ratingValue = responsePayload as? Int
                                TxlemetrySurveyResponse.Rating(ratingValue)
                            }

                            is TxlemetryDisplayChoiceQuestion -> {
                                // For single/multiple choice questions
                                if (question.isMultipleChoice) {
                                    // Multiple choice: accept array directly from Flutter.
                                    // Null and empty both mean the optional question was skipped.
                                    val selectedOptions = responsePayload as? List<*>
                                    val stringOptions = selectedOptions?.mapNotNull { it as? String }
                                    TxlemetrySurveyResponse.MultipleChoice(
                                        stringOptions?.takeIf { it.isNotEmpty() },
                                    )
                                } else {
                                    // Single choice: Flutter sends as a list with one element
                                    val selectedOptions = responsePayload as? List<*>
                                    val firstOption = selectedOptions?.firstOrNull() as? String
                                    TxlemetrySurveyResponse.SingleChoice(firstOption)
                                }
                            }

                            else -> {
                                // Default to open text question
                                val textValue = responsePayload as? String
                                TxlemetrySurveyResponse.Text(textValue)
                            }
                        }

                    // Call the callback with the constructed response
                    onSurveyResponseCallback?.invoke(survey, index, surveyResponse)?.let { nextQuestion ->
                        result.success(
                            mapOf(
                                "nextIndex" to nextQuestion.questionIndex,
                                "isSurveyCompleted" to nextQuestion.isSurveyCompleted,
                            ),
                        )
                        return
                    }
                    result.success(null)
                    return
                }
            }

            "closed" -> {
                onSurveyClosedCallback?.invoke(survey)
                // Clear the callbacks after survey is closed
                presentationId = null
                currentSurvey = null
                onSurveyShownCallback = null
                onSurveyResponseCallback = null
                onSurveyClosedCallback = null
            }
        }

        result.success(null)
    }

    /**
     * Invoke a Flutter method on the main/UI thread
     */
    private fun invokeFlutterMethod(
        method: String,
        arguments: Any? = null,
    ) {
        Handler(Looper.getMainLooper()).post {
            channel.invokeMethod(method, arguments)
        }
    }
}
