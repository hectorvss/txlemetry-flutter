package com.txlemetry.flutter

import com.txlemetry.surveys.TxlemetryDisplayChoiceQuestion
import com.txlemetry.surveys.TxlemetryDisplayLinkQuestion
import com.txlemetry.surveys.TxlemetryDisplayOpenQuestion
import com.txlemetry.surveys.TxlemetryDisplayRatingQuestion
import com.txlemetry.surveys.TxlemetryDisplaySurvey
import com.txlemetry.surveys.TxlemetryDisplaySurveyQuestion

// Convert the survey object to a map for communication with the Dart layer
// Native platform model -> Map -> Dart model
fun TxlemetryDisplaySurvey.toMap(): Map<String, Any?> {
    val map =
        mutableMapOf<String, Any?>(
            "id" to id,
            "name" to name,
            "initialQuestionIndex" to initialQuestionIndex,
            "questions" to
                questions.map { question: TxlemetryDisplaySurveyQuestion ->
                    val questionMap =
                        mutableMapOf<String, Any?>(
                            "question" to question.question,
                            "isOptional" to question.isOptional,
                            "id" to question.id,
                        )

                    questionMap["questionDescription"] = question.questionDescription
                    questionMap["questionDescriptionContentType"] = question.questionDescriptionContentType.value
                    questionMap["buttonText"] = question.buttonText

                    // Add question type-specific properties
                    when (question) {
                        is TxlemetryDisplayLinkQuestion -> {
                            questionMap["type"] = "link"
                            questionMap["link"] = question.link
                        }

                        is TxlemetryDisplayRatingQuestion -> {
                            questionMap["type"] = "rating"
                            questionMap["skipSubmitButton"] = question.skipSubmitButton
                            questionMap["ratingType"] = question.ratingType.value
                            questionMap["scaleLowerBound"] = question.scaleLowerBound
                            questionMap["scaleUpperBound"] = question.scaleUpperBound
                            questionMap["lowerBoundLabel"] = question.lowerBoundLabel
                            questionMap["upperBoundLabel"] = question.upperBoundLabel
                        }

                        is TxlemetryDisplayChoiceQuestion -> {
                            questionMap["type"] = if (question.isMultipleChoice) "multiple_choice" else "single_choice"
                            questionMap["skipSubmitButton"] = question.skipSubmitButton
                            questionMap["choices"] = question.choices
                            questionMap["hasOpenChoice"] = question.hasOpenChoice
                            questionMap["shuffleOptions"] = question.shuffleOptions
                        }

                        else -> {
                            questionMap["type"] = "open"
                        }
                    }

                    questionMap
                },
        )

    // Add appearance if available
    appearance?.let { app ->
        map["appearance"] =
            mapOf(
                "fontFamily" to app.fontFamily,
                "backgroundColor" to app.backgroundColor,
                "borderColor" to app.borderColor,
                "submitButtonColor" to app.submitButtonColor,
                "submitButtonText" to app.submitButtonText,
                "submitButtonTextColor" to app.submitButtonTextColor,
                "textColor" to app.textColor,
                "descriptionTextColor" to app.descriptionTextColor,
                "ratingButtonColor" to app.ratingButtonColor,
                "ratingButtonActiveColor" to app.ratingButtonActiveColor,
                "inputBackground" to app.inputBackground,
                "inputTextColor" to app.inputTextColor,
                "placeholder" to app.placeholder,
                "surveyPopupDelaySeconds" to app.surveyPopupDelaySeconds,
                "displayThankYouMessage" to app.displayThankYouMessage,
                "thankYouMessageHeader" to app.thankYouMessageHeader,
                "thankYouMessageDescription" to app.thankYouMessageDescription,
                "thankYouMessageDescriptionContentType" to app.thankYouMessageDescriptionContentType?.value,
                "thankYouMessageCloseButtonText" to app.thankYouMessageCloseButtonText,
                "displayIntroScreen" to app.displayIntroScreen,
                "introScreenHeader" to app.introScreenHeader,
                "introScreenDescription" to app.introScreenDescription,
                "introScreenDescriptionContentType" to app.introScreenDescriptionContentType?.value,
                "introScreenButtonText" to app.introScreenButtonText,
            )
    }

    // Add dates if available (convert to milliseconds since epoch)
    startDate?.let { date ->
        map["startDate"] = date.time
    }

    endDate?.let { date ->
        map["endDate"] = date.time
    }

    return map
}
